using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace Nhl2k8Setup
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            if (Uninstaller.Handle(args)) { return; }
            Application.Run(new SetupForm());
        }
    }

    class SetupForm : Form
    {
        const string WizardVersion = "1.3";
        const string RepoUrl = "https://github.com/anishchandra24/NHL2K8-Recompiled.git";
        const string VsWorkload = "Microsoft.VisualStudio.Workload.NativeDesktop";
        const string VsClang = "Microsoft.VisualStudio.Component.VC.Llvm.Clang";
        const string VsCmake = "Microsoft.VisualStudio.Component.VC.CMake.Project";
        const int BannerHeight = 140;

        TextBox gameBox;
        TextBox installBox;
        TextBox logBox;
        Button gameBrowse;
        Button installBrowse;
        Button startButton;
        Button playButton;
        Button logButton;
        Button uninstallButton;
        Label statusLabel;
        Process current;
        volatile bool running;
        bool browsing;
        DateTime lastBrowseClosed = DateTime.MinValue;
        string installedDir;
        readonly string logFile = Path.Combine(Path.GetTempPath(), "NHL2K8-Setup.log");
        readonly object logLock = new object();

        public SetupForm()
        {
            Text = "NHL 2K8 Recompiled - Setup";
            try { Icon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }
            Font = new Font("Segoe UI", 9f);
            Image banner = LoadBanner();
            int b = (banner != null) ? BannerHeight : 0;
            ClientSize = new Size(720, 560 + b);
            MinimumSize = new Size(640, 460 + b);
            StartPosition = FormStartPosition.CenterScreen;

            if (banner != null)
            {
                PictureBox pic = new PictureBox();
                pic.BackColor = Color.Black;
                pic.SizeMode = PictureBoxSizeMode.Zoom;
                pic.Image = banner;
                pic.SetBounds(0, 0, 720, BannerHeight);
                pic.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
                Controls.Add(pic);
            }

            Label intro = new Label();
            intro.Text = "This sets up NHL 2K8 Recompiled on your PC. It contains no game files: you need your own extracted copy of the game. " +
                "Setup downloads the project and builds it on your PC, which takes about 15 to 30 minutes and about 10 GB of disk space. " +
                "Missing tools (Git, Visual Studio) are installed for you with Windows' package installer; Windows will ask for permission.";
            intro.SetBounds(12, 10 + b, 696, 56);
            intro.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            Controls.Add(intro);

            AddRow("Your game folder (the folder that contains default.xex):", 72 + b, out gameBox, out gameBrowse);
            AddRow("Install folder (keep the path short):", 124 + b, out installBox, out installBrowse);
            installBox.Text = "C:\\NHL2K8";
            gameBrowse.Click += delegate { Browse(gameBox, "Choose the folder that contains default.xex", "game folder"); };
            installBrowse.Click += delegate { Browse(installBox, "Choose where to install (a short path such as C:\\NHL2K8)", "install folder"); };

            startButton = new Button();
            startButton.Text = "Install";
            startButton.SetBounds(12, 178 + b, 100, 32);
            startButton.Click += OnStart;
            Controls.Add(startButton);

            playButton = new Button();
            playButton.Text = "Play";
            playButton.SetBounds(118, 178 + b, 100, 32);
            playButton.Enabled = false;
            playButton.Click += OnPlay;
            Controls.Add(playButton);

            logButton = new Button();
            logButton.Text = "Open log";
            logButton.SetBounds(224, 178 + b, 100, 32);
            logButton.Click += OnOpenLog;
            Controls.Add(logButton);

            uninstallButton = new Button();
            uninstallButton.Text = "Uninstall";
            uninstallButton.SetBounds(330, 178 + b, 100, 32);
            uninstallButton.Click += OnUninstall;
            Controls.Add(uninstallButton);

            statusLabel = new Label();
            statusLabel.Text = "Ready.";
            statusLabel.AutoEllipsis = true;
            statusLabel.SetBounds(440, 186 + b, 268, 20);
            statusLabel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            Controls.Add(statusLabel);

            logBox = new TextBox();
            logBox.Multiline = true;
            logBox.ReadOnly = true;
            logBox.ScrollBars = ScrollBars.Vertical;
            logBox.Font = new Font("Consolas", 8.5f);
            logBox.BackColor = Color.White;
            logBox.SetBounds(12, 220 + b, 696, 328);
            logBox.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            Controls.Add(logBox);

            if (File.Exists("C:\\NHL2K8\\dist\\nhl2k8.exe"))
            {
                installedDir = "C:\\NHL2K8";
                playButton.Enabled = true;
                statusLabel.Text = "Already installed in C:\\NHL2K8.";
            }
            logBox.Text = "A copy of this log is saved in " + logFile + Environment.NewLine;
            string registered = Uninstaller.FindInstalled();
            if (registered != null && File.Exists(Path.Combine(registered, "dist\\nhl2k8.exe")))
            {
                installedDir = registered;
                installBox.Text = registered;
                playButton.Enabled = true;
                statusLabel.Text = "Installed in " + registered + ".";
            }
            WriteLogFile("---- NHL 2K8 Recompiled setup wizard " + WizardVersion + " started on Windows " + Environment.OSVersion.Version + " ----");
        }

        static Image LoadBanner()
        {
            try
            {
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("banner.png"))
                {
                    if (s == null) return null;
                    using (MemoryStream ms = new MemoryStream())
                    {
                        s.CopyTo(ms);
                        ms.Position = 0;
                        using (Image tmp = Image.FromStream(ms))
                        {
                            return new Bitmap(tmp);
                        }
                    }
                }
            }
            catch (Exception) { return null; }
        }

        void AddRow(string caption, int top, out TextBox box, out Button browse)
        {
            Label l = new Label();
            l.Text = caption;
            l.SetBounds(12, top, 696, 18);
            Controls.Add(l);
            box = new TextBox();
            box.SetBounds(12, top + 22, 590, 24);
            box.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            Controls.Add(box);
            browse = new Button();
            browse.Text = "Browse...";
            browse.SetBounds(612, top + 21, 96, 26);
            browse.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            Controls.Add(browse);
        }

        void Browse(TextBox box, string description, string which)
        {
            if (browsing)
            {
                WriteLogFile("Browse: ignored a request for the " + which + " dialog while another dialog was open");
                return;
            }
            double sinceClose = (DateTime.UtcNow - lastBrowseClosed).TotalMilliseconds;
            if (sinceClose < 800)
            {
                WriteLogFile("Browse: ignored a request for the " + which + " dialog " + ((int)sinceClose) + " ms after the previous dialog closed");
                return;
            }
            browsing = true;
            WriteLogFile("Browse: opening the " + which + " dialog");
            try
            {
                using (FolderBrowserDialog d = new FolderBrowserDialog())
                {
                    d.Description = description;
                    DialogResult r = d.ShowDialog(this);
                    WriteLogFile("Browse: the " + which + " dialog closed (" + r + ")");
                    if (r == DialogResult.OK) box.Text = d.SelectedPath;
                }
            }
            finally
            {
                browsing = false;
                lastBrowseClosed = DateTime.UtcNow;
            }
        }

        void WriteLogFile(string text)
        {
            lock (logLock)
            {
                try { File.AppendAllText(logFile, DateTime.Now.ToString("HH:mm:ss") + "  " + text + Environment.NewLine); } catch (Exception) { }
            }
        }

        void Log(string text)
        {
            if (text == null) return;
            WriteLogFile(text);
            try { BeginInvoke(new Action<string>(AppendUi), text); } catch (Exception) { }
        }

        void AppendUi(string text)
        {
            if (logBox.TextLength > 150000) logBox.Text = logBox.Text.Substring(logBox.TextLength - 100000);
            logBox.AppendText(text + Environment.NewLine);
        }

        void SetStatus(string s)
        {
            try { BeginInvoke(new Action(delegate { statusLabel.Text = s; })); } catch (Exception) { }
        }

        void HandleLine(string line)
        {
            if (line == null) return;
            string t = line.Trim();
            if (t.Length < 2) return;
            if (t.IndexOf('\u2588') >= 0 || t.IndexOf('\u2592') >= 0) return;
            Log(line);
        }

        void Warn(string message)
        {
            MessageBox.Show(this, message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        void OnUninstall(object sender, EventArgs e)
        {
            if (running) { Warn("Setup is still running. Wait for it to finish, or close this window to stop it."); return; }
            string dir = installBox.Text.Trim().Trim('"').TrimEnd('\\');
            int result = Uninstaller.Run(this, dir);
            if (result == 2) { Close(); return; }
            if (result == 1)
            {
                installedDir = null;
                playButton.Enabled = false;
                statusLabel.Text = "Uninstalled.";
                Log("Uninstalled " + dir);
            }
        }

        void OnOpenLog(object sender, EventArgs e)
        {
            try { Process.Start("notepad.exe", "\"" + logFile + "\""); }
            catch (Exception ex) { Warn("The log could not be opened: " + ex.Message); }
        }

        void OnStart(object sender, EventArgs e)
        {
            if (running) return;
            string game = gameBox.Text.Trim().Trim('"').TrimEnd('\\');
            string dir = installBox.Text.Trim().Trim('"').TrimEnd('\\');
            if (game.Length < 4 || !File.Exists(Path.Combine(game, "default.xex")))
            {
                Warn("default.xex was not found in the game folder you chose. Pick the folder that directly contains default.xex.");
                return;
            }
            if (dir.Length < 4)
            {
                Warn("Choose an install folder, for example C:\\NHL2K8 (not just a drive).");
                return;
            }
            if (dir.Length > 40)
            {
                Warn("The install folder path is too long (long paths can break the build). Choose a shorter one, for example C:\\NHL2K8.");
                return;
            }
            if (!Environment.Is64BitOperatingSystem)
            {
                Warn("64-bit Windows is required.");
                return;
            }
            running = true;
            startButton.Enabled = false;
            playButton.Enabled = false;
            gameBrowse.Enabled = false;
            installBrowse.Enabled = false;
            gameBox.ReadOnly = true;
            installBox.ReadOnly = true;
            Thread t = new Thread(delegate() { Work(game, dir); });
            t.IsBackground = true;
            t.Start();
        }

        void Work(string game, string dir)
        {
            bool ok = false;
            try
            {
                Log("Setup started " + DateTime.Now);
                string git = EnsureGit();
                EnsureVisualStudio();
                CloneOrPull(git, dir);
                RunSetup(git, dir, game);
                ok = File.Exists(Path.Combine(dir, "dist\\nhl2k8.exe"));
                if (!ok) throw new Exception("Setup finished but dist\\nhl2k8.exe was not created.");
                installedDir = dir;
                Uninstaller.Register(dir, new Action<string>(Log));
                Log("");
                Log("All done. Start the game with the Play button, or with the NHL 2K8 Recompiled shortcut on your desktop.");
                SetStatus("Done. Click Play.");
            }
            catch (Exception ex)
            {
                Log("");
                Log("STOPPED: " + ex.Message);
                SetStatus("Stopped - see the last lines of the log.");
            }
            try
            {
                string ld = Path.Combine(dir, ".local\\logs");
                if (Directory.Exists(ld)) File.Copy(logFile, Path.Combine(ld, "wizard.log"), true);
            }
            catch (Exception) { }
            try
            {
                BeginInvoke(new Action(delegate
                {
                    running = false;
                    startButton.Enabled = true;
                    gameBrowse.Enabled = true;
                    installBrowse.Enabled = true;
                    gameBox.ReadOnly = false;
                    installBox.ReadOnly = false;
                    playButton.Enabled = ok || (installedDir != null);
                }));
            }
            catch (Exception) { }
        }

        static string FindGit()
        {
            string[] candidates = new string[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Git\\cmd\\git.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Git\\cmd\\git.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs\\Git\\cmd\\git.exe")
            };
            foreach (string c in candidates)
            {
                if (File.Exists(c)) return c;
            }
            string path = Environment.GetEnvironmentVariable("PATH");
            if (path != null)
            {
                foreach (string p in path.Split(';'))
                {
                    if (p.Length == 0) continue;
                    try
                    {
                        string c = Path.Combine(p.Trim().Trim('"'), "git.exe");
                        if (File.Exists(c)) return c;
                    }
                    catch (Exception) { }
                }
            }
            return null;
        }

        static string Vswhere()
        {
            string p = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft Visual Studio\\Installer\\vswhere.exe");
            return File.Exists(p) ? p : null;
        }

        static string Capture(string file, string args)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(file, args);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                using (Process p = Process.Start(psi))
                {
                    string o = p.StandardOutput.ReadToEnd();
                    p.WaitForExit();
                    return o.Trim();
                }
            }
            catch (Exception) { return ""; }
        }

        static string FirstLine(string s)
        {
            if (s == null) return null;
            string[] lines = s.Split('\n');
            foreach (string l in lines)
            {
                string t = l.Trim();
                if (t.Length > 0) return t;
            }
            return null;
        }

        static string FindVs(bool requireParts)
        {
            string vswhere = Vswhere();
            if (vswhere == null) return null;
            string args = "-latest -products * -version [17.0,18.0) ";
            if (requireParts) args += "-requires " + VsClang + " " + VsCmake + " ";
            args += "-property installationPath";
            return FirstLine(Capture(vswhere, args));
        }

        string EnsureGit()
        {
            string git = FindGit();
            if (git != null)
            {
                Log("Git: found (" + git + ")");
                return git;
            }
            Log("Git was not found. Installing Git for Windows with winget...");
            Log("Windows may ask for permission (the shield prompt). Click Yes.");
            SetStatus("Installing Git...");
            RunWinget("install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements");
            git = FindGit();
            if (git == null)
                throw new Exception("Git could not be installed automatically. Install Git for Windows from https://git-scm.com/download/win and run this setup again.");
            Log("Git installed.");
            return git;
        }

        void EnsureVisualStudio()
        {
            string vs = FindVs(true);
            if (vs != null)
            {
                Log("Visual Studio 2022: found (" + vs + ")");
                return;
            }
            if (FindVs(false) != null)
            {
                Log("Visual Studio 2022 is installed, but it is missing parts this project needs.");
                try
                {
                    string installer = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft Visual Studio\\Installer\\vs_installer.exe");
                    if (File.Exists(installer)) Process.Start(installer);
                }
                catch (Exception) { }
                throw new Exception("In the Visual Studio Installer (it should have opened), click Modify, tick \"Desktop development with C++\", \"C++ Clang Compiler for Windows\" and \"C++ CMake tools for Windows\", finish the installation, then run this setup again.");
            }
            Log("Visual Studio 2022 was not found. Installing Visual Studio 2022 Community with the parts this project needs.");
            Log("This downloads several GB and can take 20 to 60 minutes. Windows will ask for permission - click Yes. A restart may be needed afterwards.");
            SetStatus("Installing Visual Studio (this takes a while)...");
            string args = "install --id Microsoft.VisualStudio.2022.Community -e --source winget --accept-source-agreements --accept-package-agreements " +
                "--override \"--passive --norestart --wait --add " + VsWorkload + " --add " + VsClang + " --add " + VsCmake + " --includeRecommended\"";
            RunWinget(args);
            if (FindVs(true) == null)
                throw new Exception("Visual Studio does not look fully installed yet. If Windows asked for a restart, restart the PC and run this setup again. Otherwise install Visual Studio 2022 Community by hand (the README lists the parts to tick).");
            Log("Visual Studio installed.");
        }

        int RunWinget(string args)
        {
            int code;
            try
            {
                code = RunProcess("winget.exe", args, null, null, true);
            }
            catch (Win32Exception)
            {
                throw new Exception("Windows' package installer (winget) was not found on this PC, so the tools cannot be installed automatically. Install Git for Windows and Visual Studio 2022 Community by hand (the README lists the parts to tick), then run this setup again.");
            }
            Log("winget finished with exit code " + code);
            return code;
        }

        void CloneOrPull(string git, string dir)
        {
            string gitDir = Path.GetDirectoryName(git);
            if (Directory.Exists(Path.Combine(dir, ".git")))
            {
                Log("The project is already downloaded. Updating it...");
                int code = RunProcess(git, "-C \"" + dir + "\" pull", null, gitDir, false);
                if (code != 0) throw new Exception("git pull failed (exit code " + code + ").");
            }
            else
            {
                if (Directory.Exists(dir) && Directory.GetFileSystemEntries(dir).Length > 0)
                    throw new Exception("The install folder already contains other files. Choose an empty folder.");
                Log("Downloading the project...");
                SetStatus("Downloading the project...");
                int code = RunProcess(git, "clone " + RepoUrl + " \"" + dir + "\"", null, gitDir, false);
                if (code != 0) throw new Exception("git clone failed (exit code " + code + ").");
            }
        }

        void RunSetup(string git, string dir, string game)
        {
            string script = Path.Combine(dir, "scripts\\setup.ps1");
            if (!File.Exists(script)) throw new Exception("The project was downloaded but scripts\\setup.ps1 is missing.");
            Log("");
            Log("Running the project's setup script...");
            SetStatus("Building the game (this is the long part)...");
            string args = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -GameDataRoot \"" + game + "\"";
            int code = RunProcess("powershell.exe", args, dir, Path.GetDirectoryName(git), false);
            if (code != 0)
                throw new Exception("Setup did not finish (exit code " + code + "). Read the messages above. You can run this installer again; finished steps are skipped.");
        }

        int RunProcess(string file, string args, string workDir, string extraPathDir, bool utf8)
        {
            ProcessStartInfo psi = new ProcessStartInfo(file, args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            if (utf8)
            {
                psi.StandardOutputEncoding = Encoding.UTF8;
                psi.StandardErrorEncoding = Encoding.UTF8;
            }
            if (workDir != null) psi.WorkingDirectory = workDir;
            if (extraPathDir != null)
                psi.EnvironmentVariables["PATH"] = extraPathDir + ";" + psi.EnvironmentVariables["PATH"];
            Process p = new Process();
            p.StartInfo = psi;
            DataReceivedEventHandler handler = delegate(object s, DataReceivedEventArgs ev) { HandleLine(ev.Data); };
            p.OutputDataReceived += handler;
            p.ErrorDataReceived += handler;
            p.Start();
            current = p;
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            p.WaitForExit();
            int code = p.ExitCode;
            current = null;
            p.Dispose();
            return code;
        }

        void OnPlay(object sender, EventArgs e)
        {
            string dir = installedDir != null ? installedDir : installBox.Text.Trim().Trim('"').TrimEnd('\\');
            string dist = Path.Combine(dir, "dist");
            string exe = Path.Combine(dist, "nhl2k8.exe");
            if (!File.Exists(exe))
            {
                Warn("The game was not found in " + dist + ". Click Install first.");
                return;
            }
            ProcessStartInfo psi = new ProcessStartInfo(exe, "--game_data_root=\"" + Path.Combine(dir, "assets") + "\" --gpu_plugin=xenos --mnk_mode=true --log_level=error");
            psi.WorkingDirectory = dist;
            psi.UseShellExecute = false;
            try { Process.Start(psi); }
            catch (Exception ex) { Warn("The game could not be started: " + ex.Message); }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (running)
            {
                if (MessageBox.Show(this, "Setup is still running. Stop it and close?", Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                {
                    e.Cancel = true;
                    return;
                }
                try
                {
                    Process p = current;
                    if (p != null && !p.HasExited) Process.Start("taskkill", "/T /F /PID " + p.Id);
                }
                catch (Exception) { }
            }
            base.OnFormClosing(e);
        }
    }
}

