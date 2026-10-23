# Builds NHL2K8-Recompiled-Setup.exe with the C# compiler that ships with Windows (no extra software needed).
# If docs\banner.png exists it is embedded and shown at the top of the window.
$ErrorActionPreference = "Stop"
$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { throw "The .NET Framework C# compiler was not found: $csc" }
$outDir = Join-Path $PSScriptRoot "out"
New-Item -ItemType Directory -Force $outDir | Out-Null
$manifest = Join-Path $outDir "app.manifest"
$lines = @(
    '<?xml version="1.0" encoding="utf-8"?>',
    '<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">',
    '  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">',
    '    <security>',
    '      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">',
    '        <requestedExecutionLevel level="asInvoker" uiAccess="false" />',
    '      </requestedPrivileges>',
    '    </security>',
    '  </trustInfo>',
    '</assembly>'
)
Set-Content -Path $manifest -Value $lines -Encoding ascii
$exe = Join-Path $outDir "NHL2K8-Recompiled-Setup.exe"
$extra = @()
$banner = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\docs\banner.png"))
if (Test-Path $banner) { $extra += ("/resource:" + $banner + ",banner.png"); Write-Host "banner embedded: $banner" } else { Write-Host "no docs\banner.png found - building without a banner" }
& $csc /nologo /target:winexe /platform:x64 /optimize+ /win32manifest:$manifest /out:$exe /r:System.Windows.Forms.dll /r:System.Drawing.dll $extra (Join-Path $PSScriptRoot "Installer.cs")
if ($LASTEXITCODE -ne 0) { throw "The installer did not compile (see the errors above)." }
Write-Host "built: $exe"
