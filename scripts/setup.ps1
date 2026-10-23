# NHL 2K8 Recompiled - setup script (version 0.1: checks only)
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup.ps1 -GameDataRoot "D:\path\to\extracted\game"
param(
    [string]$GameDataRoot = "",
    [switch]$ValidateOnly
)

$ExpectedSha256 = "BA4E63334FAF296019657C6E86BBD444CB05646E29FA6C7B72F4BF9709CE4225"
$ExpectedSize   = 9383936
$failed = $false

function Ok($msg)   { Write-Host "[ ok ] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red; $script:failed = $true }

Write-Host ""
Write-Host "NHL 2K8 Recompiled - setup (version 0.1: checks only, nothing is downloaded or built yet)"
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
if ($freeGB -ge 20) { Ok "$freeGB GB free on drive $($drive.Name):" } else { Warn "Only $freeGB GB free on drive $($drive.Name): (20 GB or more is recommended)" }

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

Write-Host ""
if ($failed) {
    Write-Host "Some checks failed. Fix them and run this again." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All required checks passed. (The build steps are not written yet; this is version 0.1.)" -ForegroundColor Green
    exit 0
}
