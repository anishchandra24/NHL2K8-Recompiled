# NHL 2K8 Recompiled - setup script (version 0.3.1: checks, SDK download, music patch, SDK build)
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup.ps1 -GameDataRoot "D:\path\to\extracted\game"
param(
    [string]$GameDataRoot = "",
    [switch]$ValidateOnly,
    [switch]$Rebuild,
    [switch]$SkipIcon,
    [switch]$NoShortcut
)

$ExpectedSha256 = "BA4E63334FAF296019657C6E86BBD444CB05646E29FA6C7B72F4BF9709CE4225"
$ExpectedSize   = 9383936
$SdkRepo   = "https://github.com/rexglue/rexglue-sdk"
$SdkCommit = "c94f5ebdcb3c9d1a460ca48e04f9758448f8d518"
$RepoRoot  = Split-Path -Parent $PSScriptRoot
$LocalDir  = Join-Path $RepoRoot ".local"
$SdkDir    = Join-Path $LocalDir "rexglue-sdk"
$SdkBuildDir   = Join-Path $SdkDir "out\build\win-amd64"
$SdkInstallDir = Join-Path $SdkDir "out\install\win-amd64"
$LogDir    = Join-Path $LocalDir "logs"
$StampFile = Join-Path $LocalDir "sdk-build.stamp"
$PatchFile = Join-Path $RepoRoot "patches\xmp_music.patch"
$PatchFile2 = Join-Path $RepoRoot "patches\codegen_vector_alias.patch"
$failed = $false
$sw = [Diagnostics.Stopwatch]::StartNew()
. (Join-Path $PSScriptRoot "libmspack.ps1")

function Ok($msg)   { Write-Host "[ ok ] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red; $script:failed = $true }

function Git-Run {
    param([string[]]$GitArgs)
    & git @GitArgs
    if ($LASTEXITCODE -ne 0) { throw ("git " + ($GitArgs -join " ") + " failed (exit code " + $LASTEXITCODE + ")") }
}

# Loads Visual Studio's build environment (the same thing a "Native Tools" prompt does).
function Import-VsEnvironment {
    if ($script:vsLoaded) { return }
    $script:vsLoaded = $true
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { throw "Visual Studio's vswhere.exe was not found. Install Visual Studio 2022 with the C++ Clang tools." }
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Llvm.Clang -property installationPath
    if (-not $vs) { $vs = & $vswhere -latest -products * -property installationPath }
    if (-not $vs) { throw "No Visual Studio installation was found." }
    $vs = ($vs | Select-Object -First 1).ToString().Trim()
    $vcvars = Join-Path $vs "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvars)) { throw "vcvars64.bat was not found in $vs" }
    $tmp = Join-Path $env:TEMP "nhl2k8_vsenv.bat"
    Set-Content -Path $tmp -Encoding ascii -Value @("@echo off", "call `"$vcvars`" >nul 2>&1", "set")
    $lines = & $tmp
    Remove-Item $tmp -ErrorAction SilentlyContinue
    foreach ($l in $lines) {
        $i = $l.IndexOf("=")
        if ($i -gt 0) { [Environment]::SetEnvironmentVariable($l.Substring(0, $i), $l.Substring($i + 1), "Process") }
    }
    Ok "Visual Studio build environment loaded"
}

# Runs a program, logs its output to .local\logs, and prints a progress line every 30 seconds.
function Invoke-Step {
    param([string]$Label, [string]$Exe, [string[]]$ToolArgs, [string]$WorkDir, [string]$LogName)
    New-Item -ItemType Directory -Force $LogDir | Out-Null
    $out = Join-Path $LogDir ($LogName + ".out.log")
    $err = Join-Path $LogDir ($LogName + ".err.log")
    $exePath = (Get-Command $Exe).Source
    $quoted = @()
    foreach ($a in $ToolArgs) { if ($a -match '\s') { $quoted += ('"' + $a + '"') } else { $quoted += $a } }
    Write-Host "$Label ... (full log: $out)"
    $t0 = Get-Date
    $p = Start-Process -FilePath $exePath -ArgumentList $quoted -WorkingDirectory $WorkDir -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
    $null = $p.Handle
    while (-not $p.HasExited) {
        Start-Sleep -Seconds 30
        $mins = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
        $last = ""
        try { $last = [string](Get-Content $out -Tail 1 -ErrorAction SilentlyContinue) } catch { }
        if ($last.Length -gt 90) { $last = $last.Substring(0, 90) }
        Write-Host ("   ... {0} min   {1}" -f $mins, $last)
    }
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        Write-Host "---- last lines of the output ----" -ForegroundColor Red
        if (Test-Path $out) { Get-Content $out -Tail 20 }
        if (Test-Path $err) { Get-Content $err -Tail 20 }
        throw "$Label failed (exit code $($p.ExitCode)). Full logs: $out and $err"
    }
    Ok ("$Label finished in {0:N1} minutes" -f ((Get-Date) - $t0).TotalMinutes)
}

Write-Host ""
Write-Host "NHL 2K8 Recompiled - setup (version 0.6: checks, SDK and game build, icon, shortcut)"
Write-Host ""

# Windows
if ([Environment]::Is64BitOperatingSystem) { Ok "64-bit Windows" } else { Bad "64-bit Windows is required" }

# Short folder path (very long paths break some builds on Windows)
if ($RepoRoot.Length -gt 45) { Warn "This folder path is long ($($RepoRoot.Length) characters). If the build fails with strange file errors, move the project to a short path such as C:\NHL2K8" }

# Git
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { Ok ("Git: " + (& git --version)) } else { Bad "Git was not found (install Git for Windows)" }

# CMake
# Find Visual Studio 2022 with vswhere (any edition, Program Files or Program Files (x86), any drive)
$VsRoot = "C:\NoVisualStudioFound"
$vswhereExe = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhereExe) {
    $vsPath = & $vswhereExe -latest -products * -version "[17.0,18.0)" -requires Microsoft.VisualStudio.Component.VC.Llvm.Clang -property installationPath | Select-Object -First 1
    if (-not $vsPath) { $vsPath = & $vswhereExe -latest -products * -version "[17.0,18.0)" -property installationPath | Select-Object -First 1 }
    if ($vsPath) { $VsRoot = ([string]$vsPath).Trim() }
}
$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmake) {
    $cm = Get-ChildItem "$VsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cm) {
        $env:Path = $cm.DirectoryName + ";" + $env:Path
        $cmake = Get-Command cmake -ErrorAction SilentlyContinue
        Ok "CMake is bundled with Visual Studio (setup will use it)"
    }
}
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
    $found = Get-ChildItem "$VsRoot" -Recurse -Depth 8 -Filter ninja.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { Ok "Ninja is bundled with Visual Studio (setup will use it)" ; $ninja = $found }
}
if ($ninja) { if (Get-Command ninja -ErrorAction SilentlyContinue) { Ok "Ninja found" } } else { Bad "Ninja was not found" }

# Clang
$clangPath = $null
$clang = Get-Command clang++ -ErrorAction SilentlyContinue
if ($clang) { $clangPath = $clang.Source }
else {
    $c = Get-ChildItem "$VsRoot\VC\Tools\Llvm\x64\bin\clang++.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
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
    $fixedCount = [int](@(Repair-Libmspack -SdkDir $SdkDir) | Select-Object -Last 1)
    Ok "libmspack sources ready ($fixedCount files replaced)"
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

    # ---- Vector pack patch (fixes pack instructions whose destination is also a source) ----
    $vecTarget = Join-Path $SdkDir "src\codegen\builders\vector.cpp"
    if (Select-String -Path $vecTarget -SimpleMatch "uint16_t pk[4]" -Quiet) {
        Ok "Vector pack patch already applied"
    } else {
        & git -C $SdkDir apply --whitespace=nowarn $PatchFile2
        if ($LASTEXITCODE -ne 0) {
            Warn "Vector pack patch did not apply cleanly; retrying while ignoring whitespace differences"
            & git -C $SdkDir apply --ignore-whitespace --whitespace=nowarn $PatchFile2
            if ($LASTEXITCODE -ne 0) { throw "The vector pack patch could not be applied" }
        }
        if (Select-String -Path $vecTarget -SimpleMatch "uint16_t pk[4]" -Quiet) {
            Ok "Vector pack patch applied"
        } else {
            throw "The vector pack patch reported success but the new code is not in the file"
        }
    }

    # ---- Build the SDK ----
    Write-Host ""
    Write-Host "--- Building the SDK (the slow step: expect a while the first time) ---"
    $stamp = $SdkCommit + "|" + (Get-FileHash -LiteralPath $PatchFile -Algorithm SHA256).Hash + "|" + (Get-FileHash -LiteralPath $PatchFile2 -Algorithm SHA256).Hash
    $haveStamp = (Test-Path $StampFile) -and ((Get-Content $StampFile -Raw).Trim() -eq $stamp)
    $runtimeDll = Join-Path $SdkInstallDir "bin\rexruntimerd.dll"
    if ($haveStamp -and (Test-Path $runtimeDll) -and (-not $Rebuild)) {
        Ok "SDK is already built and installed (use -Rebuild to force a fresh build)"
    } else {
        Import-VsEnvironment
        foreach ($tool in @("clang++", "ninja", "cmake")) {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is still not available after loading the Visual Studio environment" }
        }
        $cfgArgs = @("--preset", "win-amd64",
                     "-DREXGLUE_BUILD_TESTS=OFF", "-DREXGLUE_ENABLE_FIDELITYFX=OFF",
                     "-DREXGLUE_ENABLE_PERF_COUNTERS=ON", "-DREXGLUE_ENABLE_SANITIZERS=OFF",
                     "-DREXGLUE_ENABLE_TRACY=ON", "-DREXGLUE_USE_D3D12=ON", "-DREXGLUE_USE_VULKAN=OFF")
        Invoke-Step -Label "Configuring the SDK" -Exe "cmake" -ToolArgs $cfgArgs -WorkDir $SdkDir -LogName "sdk-configure"
        foreach ($cfg in @("Release", "RelWithDebInfo")) { Invoke-Step -Label "Building the SDK ($cfg)" -Exe "cmake" -ToolArgs @("--build", $SdkBuildDir, "--config", $cfg, "--parallel") -WorkDir $SdkDir -LogName "sdk-build-$cfg" }
        foreach ($cfg in @("Release", "RelWithDebInfo")) { Invoke-Step -Label "Installing the SDK ($cfg)" -Exe "cmake" -ToolArgs @("--install", $SdkBuildDir, "--config", $cfg) -WorkDir $SdkDir -LogName "sdk-install-$cfg" }
        foreach ($rel in @("bin\rexglue.exe", "bin\rexruntime.dll", "bin\rexruntimerd.dll", "bin\rexgpu-xenos.dll", "bin\rexgpu-xenosrd.dll")) {
            if (Test-Path (Join-Path $SdkInstallDir $rel)) { Ok "installed: $rel" } else { throw "missing after install: $rel" }
        }
        $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($runtimeDll))
        if ($text.Contains("cannot find a song file")) { Ok "the built runtime contains the music code" } else { Warn "could not find the music code inside the built runtime - check this" }
        # The recompiler keeps old generated code when only the recompiler changed, so regenerate it.
        $genDir = Join-Path $RepoRoot "generated\default"
        if (Test-Path -LiteralPath (Join-Path $genDir "sources.cmake")) {
            Remove-Item -LiteralPath $genDir -Recurse -Force
            Ok "old generated code removed; it will be regenerated with the rebuilt recompiler"
        }
        Set-Content -Path $StampFile -Value $stamp -Encoding ascii
    }
} catch {
    Bad $_.Exception.Message
}

. (Join-Path $PSScriptRoot "build-game.ps1")
. (Join-Path $PSScriptRoot "finish-install.ps1")
$sw.Stop()
Write-Host ""
if ($failed) {
    Write-Host "Setup stopped. Fix the problem above and run this again; finished steps are skipped." -ForegroundColor Red
    exit 1
}
Write-Host ("Done in {0:N1} minutes. The game is in {1}" -f $sw.Elapsed.TotalMinutes, (Join-Path $RepoRoot "dist")) -ForegroundColor Green
Write-Host "Start the game from the NHL 2K8 Recompiled shortcut on your desktop, or dist\Launch NHL 2K8.bat"
exit 0






