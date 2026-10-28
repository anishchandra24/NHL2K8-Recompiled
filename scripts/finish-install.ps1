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

        # 1. Get the game's own icon. The SDK's rexglue tool reads it straight from default.xex,
        #    so the game does not have to be started for this.
        if ((-not $SkipIcon) -and (-not (Test-Path $resIco))) {
            $png = $null
            try {
                $iconTool = Join-Path $SdkInstallDir "bin\rexglue.exe"
                $iconXex  = (Get-Item -LiteralPath (Join-Path $AssetsDir "default.xex")).FullName
                $iconWork = Join-Path $LocalDir "icon-extract"
                New-Item -ItemType Directory -Force $iconWork | Out-Null
                New-Item -ItemType Directory -Force $LogDir | Out-Null
                $iconArgs = "init --project-name icon --xex-path `"$iconXex`" achievements `"$iconXex`" `"$iconWork`""
                $ip = Start-Process -FilePath $iconTool -ArgumentList $iconArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $LogDir "icon-extract.out.log") -RedirectStandardError (Join-Path $LogDir "icon-extract.err.log")
                $cand = Join-Path $iconWork "icons\title.png"
                if (($ip.ExitCode -eq 0) -and (Test-Path $cand)) { $png = $cand }
            } catch { $png = $null }
            if ($png) {
                $pb = [IO.File]::ReadAllBytes($png)
                if (($pb.Length -gt 33) -and ($pb[1] -eq 0x50) -and ($pb[2] -eq 0x4E) -and ($pb[3] -eq 0x47)) {
                    $pw = ([int]$pb[16] -shl 24) -bor ([int]$pb[17] -shl 16) -bor ([int]$pb[18] -shl 8) -bor [int]$pb[19]
                    $ph = ([int]$pb[20] -shl 24) -bor ([int]$pb[21] -shl 16) -bor ([int]$pb[22] -shl 8) -bor [int]$pb[23]
                    $ms = New-Object IO.MemoryStream
                    $bw = New-Object IO.BinaryWriter($ms)
                    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)
                    if ($pw -ge 256) { $bw.Write([byte]0) } else { $bw.Write([byte]$pw) }
                    if ($ph -ge 256) { $bw.Write([byte]0) } else { $bw.Write([byte]$ph) }
                    $bw.Write([byte]0); $bw.Write([byte]0)
                    $bw.Write([uint16]1); $bw.Write([uint16]32)
                    $bw.Write([uint32]$pb.Length); $bw.Write([uint32]22)
                    $bw.Write($pb); $bw.Flush()
                    New-Item -ItemType Directory -Force $ResDir | Out-Null
                    [IO.File]::WriteAllBytes($resIco, $ms.ToArray())
                    Copy-Item $resIco $distIco -Force
                    Ok "saved the game's icon to res\nhl2k8.ico (read from default.xex, the game was not started)"
                }
            }
            if (-not (Test-Path $resIco)) { Warn "Could not read the icon from default.xex; falling back to starting the game once" }
        }

        # 1b. Fallback: the game writes nhl2k8.ico next to the exe the first time it runs.
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
