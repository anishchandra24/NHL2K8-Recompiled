# Makes sure the libmspack sources the SDK compiles are real files, not links or placeholders.
# libmspack keeps them as symbolic links. Depending on the Windows and Git setup they arrive either
# as tiny text files holding the target path, or as real links. Either way, replace them with copies.
function Repair-Libmspack {
    param([string]$SdkDir)
    $root = Join-Path $SdkDir "thirdparty\libmspack"
    $dst  = Join-Path $root "cabextract\mspack"
    $src  = Join-Path $root "libmspack\mspack"
    if (-not (Test-Path -LiteralPath $src)) { throw "The libmspack source folder is missing: $src" }
    New-Item -ItemType Directory -Force $dst | Out-Null
    $names = @()
    foreach ($e in @(Get-ChildItem -LiteralPath $dst -Force)) { if (-not $e.PSIsContainer) { $names += $e.Name } }
    foreach ($n in @("chm.h", "kwaj.h", "lit.h")) { if ($names -notcontains $n) { $names += $n } }
    $replaced = 0
    foreach ($n in $names) {
        $from = Join-Path $src $n
        if (-not (Test-Path -LiteralPath $from)) { continue }
        $to = Join-Path $dst $n
        $realFile = Get-Item -LiteralPath $from -Force
        $needCopy = $true
        $cur = Get-Item -LiteralPath $to -Force -ErrorAction SilentlyContinue
        if ($cur) {
            $isLink = [bool]($cur.Attributes -band [IO.FileAttributes]::ReparsePoint)
            if ((-not $isLink) -and ($cur.Length -eq $realFile.Length)) { $needCopy = $false }
        }
        if ($needCopy) {
            if ($cur) { [IO.File]::Delete($to) }
            Copy-Item -LiteralPath $from -Destination $to -Force
            $replaced++
        }
    }
    $lz = Join-Path $dst "lzxd.c"
    $good = $false
    $detail = "lzxd.c is missing"
    if (Test-Path -LiteralPath $lz) {
        $item = Get-Item -LiteralPath $lz -Force
        $isLink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
        $good = (-not $isLink) -and ($item.Length -gt 1000)
        $detail = "lzxd.c attributes=" + $item.Attributes + " length=" + $item.Length
    }
    if (-not $good) {
        $sym = ""
        try { $sym = [string](& git -C $SdkDir config core.symlinks 2>$null) } catch { }
        throw ("The libmspack sources are not usable. " + $detail + "; core.symlinks=" + $sym)
    }
    return $replaced
}
