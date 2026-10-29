using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Nhl2k8Setup
{
    static class Uninstaller
    {
        const string RegKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\NHL2K8Recompiled";
        const string Title = "NHL 2K8 Recompiled - Uninstall";
        const string CopyName = "NHL2K8-Recompiled-Setup.exe";

        // Command line: /uninstall [folder]   /uninstall-copy folder   /register [folder]
        public static bool Handle(string[] args)
        {
            if (args == null || args.Length == 0) return false;
            string first = args[0].ToLowerInvariant();
            string dir = (args.Length > 1) ? args[1] : Path.GetDirectoryName(Application.ExecutablePath);
            if (first == "/uninstall") { Run(null, dir, false); return true; }
            if (first == "/uninstall-copy") { Run(null, dir, true); return true; }
            if (first == "/register")
            {
                Register(Normalize(dir), delegate(string s) { MessageBox.Show(s, Title); });
                return true;
            }
            return false;
        }

        public static string FindInstalled()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RegKey))
                {
                    if (k == null) return null;
                    string loc = k.GetValue("InstallLocation") as string;
                    if (loc != null && Directory.Exists(loc)) return loc;
                }
            }
            catch (Exception) { }
            return null;
        }

        // Puts a copy of this program in the install folder and adds the entry to Windows' list of installed apps.
        public static void Register(string dir, Action<string> log)
        {
            if (dir == null) return;
            try
            {
                string copy = Path.Combine(dir, CopyName);
                string me = Application.ExecutablePath;
                if (!SamePath(me, copy)) File.Copy(me, copy, true);
                string dist = Path.Combine(dir, "dist");
                string ico = Path.Combine(dist, "nhl2k8.ico");
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(RegKey))
                {
                    k.SetValue("DisplayName", "NHL 2K8 Recompiled");
                    k.SetValue("DisplayVersion", "0.1");
                    k.SetValue("Publisher", "anishchandra24");
                    k.SetValue("InstallLocation", dir);
                    k.SetValue("DisplayIcon", File.Exists(ico) ? ico : Path.Combine(dist, "nhl2k8.exe"));
                    k.SetValue("UninstallString", "\"" + copy + "\" /uninstall \"" + dir + "\"");
                    k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                    k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                }
                log("Added to Windows' list of installed apps (Settings, Apps). Uninstaller: " + copy);
            }
            catch (Exception ex) { log("Could not add the uninstall entry: " + ex.Message); }
        }

        // Returns 0 = nothing was removed, 1 = removed, 2 = continuing in a temporary copy (the caller must exit).
        public static int Run(IWin32Window owner, string dir)
        {
            return Run(owner, dir, false);
        }

        public static int Run(IWin32Window owner, string dir, bool fromCopy)
        {
            try
            {
                dir = Normalize(dir);
                string problem = CheckFolder(dir);
                if (problem != null)
                {
                    MessageBox.Show(owner, problem, Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return 0;
                }
                if (GameIsRunning(dir))
                {
                    MessageBox.Show(owner, "The game is running. Close it and try again.", Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return 0;
                }
                if (!fromCopy && IsInside(Application.ExecutablePath, dir))
                {
                    // The uninstaller cannot delete the folder it runs from, so it continues from a copy in
                    // the temporary folder. That copy is left there for Windows' cleanup to remove.
                    string tmp = Path.Combine(Path.GetTempPath(), "NHL2K8-Recompiled-Uninstall.exe");
                    File.Copy(Application.ExecutablePath, tmp, true);
                    ProcessStartInfo relaunch = new ProcessStartInfo(tmp, "/uninstall-copy \"" + dir + "\"");
                    relaunch.UseShellExecute = false;
                    Process.Start(relaunch);
                    return 2;
                }

                string assetsPath = Path.Combine(dir, "assets");
                bool assetsIsLink = IsReparse(assetsPath);
                bool assetsIsRealFolder = (!assetsIsLink) && Directory.Exists(assetsPath);

                string msg = "This removes NHL 2K8 Recompiled from:\r\n" + dir +
                    "\r\n\r\nIt does NOT touch your game files, Git or Visual Studio.";
                if (assetsIsRealFolder) msg += "\r\n\r\nThe 'assets' folder inside it holds real files (it is not a link to your game folder), so it will be kept.";
                msg += "\r\n\r\nContinue?";
                if (MessageBox.Show(owner, msg, Title, MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) != DialogResult.Yes) return 0;

                string docs = Environment.GetEnvironmentVariable("NHL2K8_DOCS_OVERRIDE");
                if (string.IsNullOrEmpty(docs)) docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
                string saves = Path.Combine(docs, "nhl2k8");
                bool deleteSaves = false;
                if (Directory.Exists(saves))
                {
                    string m2 = "Your saves, achievements, settings and shader cache are stored in:\r\n" + saves +
                        "\r\n\r\nEvery build of this game on this PC shares them. Delete them too?\r\n\r\nYes = delete them permanently\r\nNo = keep them (recommended)";
                    deleteSaves = MessageBox.Show(owner, m2, Title, MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) == DialogResult.Yes;
                }

                if (fromCopy) Thread.Sleep(1500);

                // The link to the game folder goes first, and everything stops if it cannot be removed.
                if (assetsIsLink)
                {
                    RunCmd("rmdir \"" + assetsPath + "\"");
                    if (IsReparse(assetsPath) || Directory.Exists(assetsPath))
                        throw new Exception("The link to your game folder could not be removed, so nothing was deleted. Your game files are safe.");
                }

                bool leftovers = false;
                if (assetsIsRealFolder)
                {
                    foreach (string d in Directory.GetDirectories(dir))
                    {
                        if (!SamePath(d, assetsPath)) { if (!DeleteDir(d)) leftovers = true; }
                    }
                    foreach (string f in Directory.GetFiles(dir))
                    {
                        if (!DeleteFileSafe(f)) leftovers = true;
                    }
                }
                else
                {
                    if (!DeleteDir(dir)) leftovers = true;
                }

                // Desktop shortcut, only if it points into the removed folder
                try
                {
                    string lnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "NHL 2K8 Recompiled.lnk");
                    if (File.Exists(lnk))
                    {
                        string target = ShortcutTarget(lnk);
                        if (target != null && IsInside(target, dir)) File.Delete(lnk);
                    }
                }
                catch (Exception) { }

                RemoveRegistration(dir);

                bool savesProblem = false;
                if (deleteSaves) { if (!DeleteDir(saves)) savesProblem = true; }

                string done = "NHL 2K8 Recompiled was removed from " + dir + ".";
                if (leftovers) done += "\r\n\r\nSome files could not be deleted. Close anything that is using them and delete the folder by hand.";
                if (assetsIsRealFolder) done += "\r\n\r\nThe 'assets' folder was kept because it holds real files.";
                if (deleteSaves) done += savesProblem ? "\r\n\r\nSome of your saves could not be deleted." : "\r\n\r\nYour saves and settings were deleted.";
                else if (Directory.Exists(saves)) done += "\r\n\r\nYour saves and settings were kept.";
                done += "\r\n\r\nYour game folder, Git and Visual Studio were not touched.";
                MessageBox.Show(owner, done, Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 1;
            }
            catch (Exception ex)
            {
                MessageBox.Show(owner, "The uninstall stopped: " + ex.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return 0;
            }
        }

        static string CheckFolder(string dir)
        {
            if (dir == null || dir.Length < 6) return "That install folder is not valid.";
            if (!Directory.Exists(dir)) return "The folder does not exist:\r\n" + dir;
            if (SamePath(dir, Path.GetPathRoot(dir))) return "That is a whole drive, not an install folder.";
            if (!File.Exists(Path.Combine(dir, "setup.bat")) || !File.Exists(Path.Combine(dir, "scripts\\setup.ps1")) || !File.Exists(Path.Combine(dir, "nhl2k8_manifest.toml")))
                return "This does not look like an NHL 2K8 Recompiled install folder, so nothing was changed:\r\n" + dir;
            return null;
        }

        static bool GameIsRunning(string dir)
        {
            foreach (Process p in Process.GetProcessesByName("nhl2k8"))
            {
                try { if (IsInside(p.MainModule.FileName, dir)) return true; }
                catch (Exception) { }
            }
            return false;
        }

        static string Normalize(string dir)
        {
            if (dir == null) return null;
            try { return Path.GetFullPath(dir.Trim().Trim('"')).TrimEnd('\\'); }
            catch (Exception) { return null; }
        }

        static bool SamePath(string a, string b)
        {
            if (a == null || b == null) return false;
            try { return string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); }
            catch (Exception) { return false; }
        }

        static bool IsInside(string path, string dir)
        {
            if (path == null || dir == null) return false;
            try
            {
                string p = Path.GetFullPath(path);
                string d = Path.GetFullPath(dir).TrimEnd('\\') + "\\";
                return p.StartsWith(d, StringComparison.OrdinalIgnoreCase);
            }
            catch (Exception) { return false; }
        }

        static bool IsReparse(string path)
        {
            try { return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0; }
            catch (Exception) { return false; }
        }

        static int RunCmd(string args)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/c " + args);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit();
                    return p.ExitCode;
                }
            }
            catch (Exception) { return -1; }
        }

        static bool DeleteDir(string path)
        {
            for (int i = 0; i < 3; i++)
            {
                if (!Directory.Exists(path)) return true;
                RunCmd("rmdir /s /q \"" + path + "\"");
                if (!Directory.Exists(path)) return true;
                Thread.Sleep(1000);
            }
            return !Directory.Exists(path);
        }

        static bool DeleteFileSafe(string path)
        {
            try { File.SetAttributes(path, FileAttributes.Normal); File.Delete(path); }
            catch (Exception) { }
            return !File.Exists(path);
        }

        static string ShortcutTarget(string lnk)
        {
            try
            {
                Type t = Type.GetTypeFromProgID("WScript.Shell");
                object shell = Activator.CreateInstance(t);
                object link = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnk });
                object target = link.GetType().InvokeMember("TargetPath", BindingFlags.GetProperty, null, link, null);
                return target as string;
            }
            catch (Exception) { return null; }
        }

        static void RemoveRegistration(string dir)
        {
            try
            {
                string loc = null;
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RegKey))
                {
                    if (k != null) loc = k.GetValue("InstallLocation") as string;
                }
                if (loc != null && SamePath(loc, dir)) Registry.CurrentUser.DeleteSubKey(RegKey, false);
            }
            catch (Exception) { }
        }
    }
}
