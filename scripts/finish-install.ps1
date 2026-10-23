# NHL 2K8 Recompiled - icon and desktop shortcut.
# Run by setup.ps1 after the game is built; shares its variables and helper functions.

if (-not $failed) {
    try {
        Write-Host ""
        Write-Host "--- Icon and shortcut ---"
        $DistDir      = Join-Path $RepoRoot "dist"
        $ResDir       = Join-Path $RepoRoot "res"
        $AssetsDir    = Join-Path $RepoRoot "assets"
        $GameBuildDir = Join-Path $RepoRoot "out\build\win-amd64-relwithdebinfo"
        $exe          = Join-Path $DistDir "nhl2k8.exe"
        $distIco      = Join-Path $DistDir "nhl2k8.ico"
        $resIco       = Join-Path $ResDir "nhl2k8.ico"
        $iconStamp    = Join-Path $LocalDir "icon-embedded.stamp"

        # 1. Get the game's own icon. The game writes nhl2k8.ico next to the exe the first time it runs.
        if ((-not $SkipIcon) -and (-not (Test-Path $resIco))) {
            if (-not (Test-Path $distIco)) {
                Write-Host "The game will open for a few seconds to make its icon, then close by itself."
                Write-Host "(If Windows asks about the firewall, you can click Cancel.)"
                $p = Start-Process -FilePath $exe -WorkingDirectory $DistDir -PassThru -ArgumentList @(("--game_data_root=`"" + $AssetsDir + "`""), "--gpu_plugin=xenos", "--mnk_mode=true", "--log_level=error")
                $deadline = (Get-Date).AddSeconds(90)
                while ((-not (Test-Path $distIco)) -and (-not $p.HasExited) -and ((Get-Date) -lt $deadline)) { Start-Sleep -Seconds 2 }
                Start-Sleep -Seconds 3
                if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
            }
            if (Test-Path $distIco) {
                New-Item -ItemType Directory -Force $ResDir | Out-Null
                Copy-Item $distIco $resIco -Force
                Ok "saved the game's icon to res\nhl2k8.ico"
            } else {
                Warn "The icon file was not created. The exe keeps the generic icon (the window and taskbar icons still work)."
            }
        }

        # 2. Embed it in the exe (shown in File Explorer). Skipped if already done for this icon.
        if ((-not $SkipIcon) -and (Test-Path $resIco)) {
            $icoHash = (Get-FileHash -LiteralPath $resIco -Algorithm SHA256).Hash
            $done = (Test-Path $iconStamp) -and ((Get-Content $iconStamp -Raw).Trim() -eq $icoHash)
            if ($done) {
                Ok "the exe already carries the game icon"
            } else {
                Import-VsEnvironment
                $prefix = $SdkInstallDir.Replace('\', '/')
                $gameCfg = @("--preset", "win-amd64-relwithdebinfo", ("-DCMAKE_PREFIX_PATH=" + $prefix))
                Invoke-Step -Label "Configuring the game (to embed the icon)" -Exe "cmake" -ToolArgs $gameCfg -WorkDir $RepoRoot -LogName "game-configure3"
                Invoke-Step -Label "Rebuilding the game with its icon" -Exe "cmake" -ToolArgs @("--build", $GameBuildDir, "--parallel", "4") -WorkDir $RepoRoot -LogName "game-build2"
                Copy-Item (Join-Path $GameBuildDir "nhl2k8.exe") $DistDir -Force
                Set-Content -Path $iconStamp -Value $icoHash -Encoding ascii
                Ok "the exe now carries the game icon"
            }
        }

        # 3. Desktop shortcut
        if (-not $NoShortcut) {
            $desktop = [Environment]::GetFolderPath("Desktop")
            $lnkPath = Join-Path $desktop "NHL 2K8 Recompiled.lnk"
            $ws = New-Object -ComObject WScript.Shell
            $lnk = $ws.CreateShortcut($lnkPath)
            $lnk.TargetPath = $exe
            $lnk.Arguments = "--game_data_root=`"$AssetsDir`" --gpu_plugin=xenos --mnk_mode=true --log_level=error"
            $lnk.WorkingDirectory = $DistDir
            if (Test-Path $distIco) { $lnk.IconLocation = $distIco + ",0" } else { $lnk.IconLocation = $exe + ",0" }
            $lnk.Description = "NHL 2K8 Recompiled"
            $lnk.Save()
            Ok "desktop shortcut created: $lnkPath"
        } else {
            Ok "skipped the desktop shortcut"
        }
    } catch {
        Bad $_.Exception.Message
    }
}
