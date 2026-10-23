# NHL 2K8 Recompiled - setup script (version 0.2.1: checks, fetches the SDK, applies the music patch)
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup.ps1 -GameDataRoot "D:\path\to\extracted\game"
param(
    [string]$GameDataRoot = "",
    [switch]$ValidateOnly
)

$ExpectedSha256 = "BA4E63334FAF296019657C6E86BBD444CB05646E29FA6C7B72F4BF9709CE4225"
$ExpectedSize   = 9383936
$SdkRepo   = "https://github.com/rexglue/rexglue-sdk"
$SdkCommit = "c94f5ebdcb3c9d1a460ca48e04f9758448f8d518"
$RepoRoot  = Split-Path -Parent $PSScriptRoot
$LocalDir  = Join-Path $RepoRoot ".local"
$SdkDir    = Join-Path $LocalDir "rexglue-sdk"
$PatchFile = Join-Path $RepoRoot "patches\xmp_music.patch"
$failed = $false
$sw = [Diagnostics.Stopwatch]::StartNew()

function Ok($msg)   { Write-Host "[ ok ] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red; $script:failed = $true }
function Git-Run {
    param([string[]]$GitArgs)
    & git @GitArgs
    if ($LASTEXITCODE -ne 0) { throw ("git " + ($GitArgs -join " ") + " failed (exit code " + $LASTEXITCODE + ")") }
}

Write-Host ""
Write-Host "NHL 2K8 Recompiled - setup (version 0.2.1: checks, SDK download, music patch; no build yet)"
Write-Host ""

# Windows
if ([Environment]::Is64BitOperatingSystem) { Ok "64-bit Windows" } else { Bad "64-bit Windows is required" }

# Git
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { Ok ("Git: " + (& git --version)) } else { Bad "Git was not found (install Git for Windows)" }

# CMake
$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if ($cmake) {
    $line = (& cmake --version | Select-Object -First 1)
    $ver = [regex]::Match($line, '(\d+)\.(\d+)')
    $okver = $false
    if ($ver.Success) {
        $maj = [int]$ver.Groups[1].Value
        $min = [int]$ver.Groups[2].Value
        $okver = ($maj -gt 3) -or ($maj -eq 3 -and $min -ge 25)
    }
    if ($okver) { Ok $line } else { Bad "$line - CMake 3.25 or newer is required" }
} else { Bad "CMake was not found" }

# Ninja
$ninja = Get-Command ninja -ErrorAction SilentlyContinue
if (-not $ninja) {
    $found = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\2022" -Recurse -Depth 8 -Filter ninja.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { Warn ("Ninja is bundled with Visual Studio (" + $found.FullName + ") but is not on PATH") ; $ninja = $found }
}
if ($ninja) { Ok "Ninja found" } else { Bad "Ninja was not found" }

# Clang
$clangPath = $null
$clang = Get-Command clang++ -ErrorAction SilentlyContinue
if ($clang) { $clangPath = $clang.Source }
else {
    $c = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\2022\*\VC\Tools\Llvm\x64\bin\clang++.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { $clangPath = $c.FullName }
}
if ($clangPath) { Ok ("Clang: " + (& $clangPath --version | Select-Object -First 1)) } else { Bad "Clang (the C++ Clang tools for Visual Studio 2022) was not found" }

# Disk space
$drive = (Get-Item $PSScriptRoot).PSDrive
$freeGB = [math]::Round($drive.Free / 1GB)
if ($freeGB -ge 10) { Ok "$freeGB GB free on drive $($drive.Name):" } else { Warn "Only $freeGB GB free on drive $($drive.Name): (10 GB or more is recommended)" }

# Game folder
if (-not $GameDataRoot) { $GameDataRoot = Read-Host "Path to your extracted NHL 2K8 game folder (the one containing default.xex)" }
$GameDataRoot = $GameDataRoot.Trim().Trim('"')
$xex = Join-Path $GameDataRoot "default.xex"
if (-not (Test-Path -LiteralPath $xex)) {
    Bad "default.xex was not found in '$GameDataRoot'"
} else {
    Ok "Found default.xex"
    $size = (Get-Item -LiteralPath $xex).Length
    $hash = (Get-FileHash -LiteralPath $xex -Algorithm SHA256).Hash
    if ($hash -eq $ExpectedSha256) {
        Ok "default.xex matches the supported version (SHA-256 verified)"
    } else {
        Warn "default.xex is NOT the version this port was made with."
        Warn "  yours:     $hash ($size bytes)"
        Warn "  supported: $ExpectedSha256 ($ExpectedSize bytes)"
        Warn "  The generated code only fits the supported version; a different release will probably misbehave."
    }
    $count = (Get-ChildItem -LiteralPath $GameDataRoot -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    Ok "$count files in the game folder"
}

if ($failed) {
    Write-Host ""
    Write-Host "Some checks failed. Fix them and run this again." -ForegroundColor Red
    exit 1
}
if ($ValidateOnly) {
    Write-Host ""
    Write-Host "All required checks passed (validate-only mode)." -ForegroundColor Green
    exit 0
}

# ---- SDK ----
Write-Host ""
Write-Host "--- ReXGlue SDK ---"
try {
    New-Item -ItemType Directory -Force $LocalDir | Out-Null
    if (-not (Test-Path (Join-Path $SdkDir ".git"))) {
        New-Item -ItemType Directory -Force $SdkDir | Out-Null
        Git-Run @("-C", $SdkDir, "init", "-q")
        Git-Run @("-C", $SdkDir, "remote", "add", "origin", $SdkRepo)
    }
    $head = (& git -C $SdkDir rev-parse HEAD 2>$null)
    if ($head -eq $SdkCommit) {
        Ok "SDK is already at the right commit"
    } else {
        Write-Host "Downloading the ReXGlue SDK (this can take several minutes)..."
        Git-Run @("-C", $SdkDir, "fetch", "--tags", "origin")
        Git-Run @("-C", $SdkDir, "checkout", "-q", "-f", $SdkCommit)
        Ok "SDK checked out at $SdkCommit"
    }
    Write-Host "Downloading the SDK's bundled libraries (this is the big part)..."
    try {
        Git-Run @("-C", $SdkDir, "submodule", "update", "--init", "--recursive", "--depth", "1")
    } catch {
        Warn "Shallow download failed; retrying with the full history (slower)"
        Git-Run @("-C", $SdkDir, "submodule", "update", "--init", "--recursive")
    }
    Ok "Bundled libraries ready"
    # libmspack ships its sources as symlinks. Windows Git without symlink support turns
    # them into tiny text files holding the target path. Put the real files in place.
    $mspackDir = Join-Path $SdkDir "thirdparty\libmspack\cabextract\mspack"
    $fixed = 0
    foreach ($f in Get-ChildItem $mspackDir -File) {
        if ($f.Length -lt 100) {
            $rel = (Get-Content -LiteralPath $f.FullName -Raw).Trim()
            if ($rel -like "../*") {
                $src = [IO.Path]::GetFullPath((Join-Path $mspackDir $rel))
                if (Test-Path -LiteralPath $src) {
                    Copy-Item -LiteralPath $src -Destination $f.FullName -Force
                    $fixed++
                }
            }
        }
    }
    foreach ($n in @("chm.h", "kwaj.h", "lit.h")) {
        $src = Join-Path $SdkDir ("thirdparty\libmspack\libmspack\mspack\" + $n)
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $mspackDir $n) -Force }
    }
    if ((Get-Item (Join-Path $mspackDir "lzxd.c")).Length -gt 1000) {
        Ok "libmspack sources ready ($fixed placeholder files replaced)"
    } else {
        throw "libmspack sources are still placeholders"
    }
    Ok ("SDK version: " + (& git -C $SdkDir describe --tags --always))

    $target = Join-Path $SdkDir "src\kernel\xam\apps\xmp_app.cpp"
    if (Select-String -Path $target -SimpleMatch "class MusicPlayer" -Quiet) {
        Ok "Music patch already applied"
    } else {
        & git -C $SdkDir apply --whitespace=nowarn $PatchFile
        if ($LASTEXITCODE -ne 0) {
            Warn "Patch did not apply cleanly; retrying while ignoring whitespace differences"
            & git -C $SdkDir apply --ignore-whitespace --whitespace=nowarn $PatchFile
            if ($LASTEXITCODE -ne 0) { throw "The music patch could not be applied" }
        }
        if (Select-String -Path $target -SimpleMatch "class MusicPlayer" -Quiet) {
            Ok "Music patch applied"
        } else {
            throw "The patch reported success but the music code is not in the file"
        }
    }
} catch {
    Bad $_.Exception.Message
}

$sw.Stop()
Write-Host ""
if ($failed) {
    Write-Host "Setup stopped. Fix the problem above and run this again; finished steps are skipped." -ForegroundColor Red
    exit 1
}
Write-Host ("Done in {0:N1} minutes. The patched SDK source is at {1}" -f $sw.Elapsed.TotalMinutes, $SdkDir) -ForegroundColor Green
Write-Host "(The build steps are not written yet; this is version 0.2.1.)"
exit 0

