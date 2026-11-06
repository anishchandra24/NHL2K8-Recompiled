// NHL 2K8 Recompiled - roster import.
//
// Community rosters for NHL 2K8 are Xbox 360 save files (.ROS, an STFS "CON" package
// holding one file, SaveGame.dat), often shared inside a .zip. The recompiled game keeps
// its saves as plain folders:
//   Documents\nhl2k8\<profile id>\54540809\00000001\<name>.ROS\SaveGame.dat
//   Documents\nhl2k8\<profile id>\54540809\Headers\00000001\<name>.ROS.header
// This unpacks SaveGame.dat from the package and writes both, so the roster shows up
// in the game's Load Roster list. Nothing that exists is overwritten.

using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;

namespace Nhl2k8Setup
{
    public class RosterFile
    {
        public string Source;       // where it came from (for messages)
        public string DisplayName;  // suggested name for the in-game list
        public byte[] Data;         // SaveGame.dat
    }

    public static class RosterImport
    {
        public const uint TitleId = 0x54540809;
        const uint SavedGame = 1;  // XContent type of game saves
        const string DefaultProfile = "B13EBABEBABEBABE";

        public static string SavesRoot()
        {
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "nhl2k8");
        }

        // Reads a .ROS, a .zip with .ROS files inside, or a loose SaveGame.dat.
        public static List<RosterFile> Load(string path)
        {
            List<RosterFile> found = new List<RosterFile>();
            string ext = Path.GetExtension(path).ToLowerInvariant();
            if (ext == ".rar" || ext == ".7z")
                throw new Exception("This is a " + ext + " archive. Unpack it first (for example with 7-Zip), then choose the .ROS file inside.");
            if (ext == ".zip")
            {
                using (ZipArchive zip = ZipFile.OpenRead(path))
                {
                    foreach (ZipArchiveEntry e in zip.Entries)
                    {
                        string n = e.Name.ToLowerInvariant();
                        if (!n.EndsWith(".ros") && n != "savegame.dat") continue;
                        if (e.Length > 16 * 1024 * 1024) continue;
                        byte[] bytes;
                        using (Stream s = e.Open())
                        using (MemoryStream m = new MemoryStream())
                        {
                            s.CopyTo(m);
                            bytes = m.ToArray();
                        }
                        found.Add(FromBytes(bytes, Path.GetFileName(path) + " > " + e.FullName,
                            Path.GetFileNameWithoutExtension(path)));
                    }
                }
                if (found.Count == 0) throw new Exception("No .ROS roster file was found inside " + Path.GetFileName(path) + ".");
                return found;
            }
            FileInfo fi = new FileInfo(path);
            if (fi.Length > 16 * 1024 * 1024) throw new Exception(Path.GetFileName(path) + " is too big to be a roster file.");
            found.Add(FromBytes(File.ReadAllBytes(path), Path.GetFileName(path), Path.GetFileNameWithoutExtension(path)));
            return found;
        }

        static RosterFile FromBytes(byte[] b, string source, string fallbackName)
        {
            RosterFile r = new RosterFile();
            r.Source = source;
            string magic = b.Length >= 4 ? Encoding.ASCII.GetString(b, 0, 4) : "";
            if (magic == "CON " || magic == "LIVE" || magic == "PIRS")
            {
                if (b.Length < 0xA000) throw new Exception(source + " is not a complete Xbox 360 save.");
                if (BE32(b, 0x360) != TitleId) throw new Exception(source + " is a save from a different game, not NHL 2K8.");
                if (BE32(b, 0x344) != SavedGame) throw new Exception(source + " is not a saved-game file.");
                r.Data = ExtractSaveGame(b, source);
                string dn = Encoding.BigEndianUnicode.GetString(b, 0x411, 0x80);
                int z = dn.IndexOf('\0');
                if (z >= 0) dn = dn.Substring(0, z);
                r.DisplayName = dn.Trim();
            }
            else
            {
                r.Data = b;
            }
            if (r.DisplayName == null || r.DisplayName.Length == 0 || r.DisplayName == "Roster")
                r.DisplayName = fallbackName;
            if (Regex.IsMatch(r.DisplayName, "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{8}$") || r.DisplayName.Equals("SaveGame", StringComparison.OrdinalIgnoreCase))
                r.DisplayName = "Imported Roster";  // a file name, not a real name
            r.DisplayName = CleanName(r.DisplayName);
            if (r.DisplayName.Length == 0) r.DisplayName = "Imported Roster";
            CheckRoster(r.Data, source);
            return r;
        }

        // A roster is about 1.1 MB and holds the game's team list (for example the
        // classic team "Red Wings '52", code DET52). Franchise and profile saves are refused.
        static void CheckRoster(byte[] d, string source)
        {
            if (d.Length < 512 * 1024 || d.Length > 2 * 1024 * 1024)
                throw new Exception(source + " does not look like an NHL 2K8 roster (wrong size; franchise and season saves can't be imported).");
            byte[] code = Encoding.ASCII.GetBytes("DET52\0");
            if (IndexOf(d, code) < 0)
                throw new Exception(source + " does not look like an NHL 2K8 roster.");
        }

        // STFS: the file table and the file's blocks, with the hash-table blocks skipped.
        static byte[] ExtractSaveGame(byte[] b, string source)
        {
            uint headerSize = BE32(b, 0x340);
            long baseOffset = (headerSize + 0xFFF) & ~0xFFFL;
            int vd = 0x379;
            int perHashTable = ((b[vd + 2] & 1) != 0) ? 1 : 2;
            int tableBlocks = b[vd + 3] | (b[vd + 4] << 8);
            int tableBlock = b[vd + 5] | (b[vd + 6] << 8) | (b[vd + 7] << 16);
            for (int t = 0; t < tableBlocks; t++)
            {
                long tableOff = BlockOffset(tableBlock + t, baseOffset, perHashTable);
                for (int i = 0; i < 64; i++)
                {
                    long e = tableOff + i * 64;
                    if (e + 64 > b.Length || b[e] == 0) break;
                    int flags = b[e + 40];
                    int nameLen = flags & 0x3F;
                    string name = Encoding.ASCII.GetString(b, (int)e, nameLen);
                    if (!name.Equals("SaveGame.dat", StringComparison.OrdinalIgnoreCase)) continue;
                    if ((flags & 0x80) != 0) continue;  // a folder
                    if ((flags & 0x40) == 0)
                        throw new Exception(source + ": this save is stored in a layout the importer doesn't read (not one continuous run). Please report it.");
                    int blocks = b[e + 41] | (b[e + 42] << 8) | (b[e + 43] << 16);
                    int start = b[e + 47] | (b[e + 48] << 8) | (b[e + 49] << 16);
                    int size = (int)BE32(b, (int)e + 52);
                    if (size <= 0 || (long)blocks * 4096 < size) throw new Exception(source + ": the save's file table is damaged.");
                    byte[] data = new byte[size];
                    int done = 0;
                    for (int n = 0; n < blocks && done < size; n++)
                    {
                        long off = BlockOffset(start + n, baseOffset, perHashTable);
                        int len = Math.Min(4096, size - done);
                        if (off + len > b.Length) throw new Exception(source + " is cut short (incomplete download?).");
                        Buffer.BlockCopy(b, (int)off, data, done, len);
                        done += len;
                    }
                    return data;
                }
            }
            throw new Exception(source + " has no SaveGame.dat inside.");
        }

        static long BlockOffset(int block, long baseOffset, int perHashTable)
        {
            long n = block;
            int[] levels = { 170, 28900, 4913000 };
            foreach (int level in levels)
            {
                n += ((block + level) / level) * perHashTable;
                if (block < level) break;
            }
            return baseOffset + (n << 12);
        }

        public static string CleanName(string s)
        {
            StringBuilder sb = new StringBuilder();
            foreach (char c in (s ?? ""))
            {
                if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || " -'.".IndexOf(c) >= 0)
                    sb.Append(c);
                else if (c == '_')
                    sb.Append(' ');
            }
            string t = Regex.Replace(sb.ToString(), " +", " ").Trim();
            if (t.Length > 24) t = t.Substring(0, 24).Trim();
            return t;
        }

        // The profile folder the game saves into (normally B13EBABEBABEBABE).
        public static string ProfileDir()
        {
            string root = SavesRoot();
            string pick = null;
            if (Directory.Exists(root))
            {
                foreach (string d in Directory.GetDirectories(root))
                {
                    string n = Path.GetFileName(d).ToUpperInvariant();
                    if (!Regex.IsMatch(n, "^[0-9A-F]{16}$")) continue;
                    if (!Directory.Exists(Path.Combine(d, "54540809"))) continue;
                    if (n == DefaultProfile) return d;
                    if (pick == null) pick = d;
                }
            }
            return pick ?? Path.Combine(root, DefaultProfile);
        }

        // Writes the roster as a new save. Returns the save's folder.
        public static string Install(RosterFile r, string displayName)
        {
            string title = Path.Combine(ProfileDir(), "54540809");
            string saves = Path.Combine(title, "00000001");
            string headers = Path.Combine(title, "Headers", "00000001");
            Random rnd = new Random();
            string fileName;
            do
            {
                fileName = rnd.Next().ToString("X8") + "-" + rnd.Next().ToString("X8") + ".ROS";
            } while (Directory.Exists(Path.Combine(saves, fileName)) || File.Exists(Path.Combine(headers, fileName + ".header")));

            byte[] h = new byte[0x148];
            PutBE32(h, 0x000, 1);          // device: hard drive
            PutBE32(h, 0x004, SavedGame);  // content type
            byte[] dn = Encoding.BigEndianUnicode.GetBytes(displayName);
            Buffer.BlockCopy(dn, 0, h, 0x008, Math.Min(dn.Length, 254));
            byte[] fn = Encoding.ASCII.GetBytes(fileName);
            Buffer.BlockCopy(fn, 0, h, 0x108, Math.Min(fn.Length, 41));
            PutBE32(h, 0x140, TitleId);

            string dir = Path.Combine(saves, fileName);
            Directory.CreateDirectory(dir);
            Directory.CreateDirectory(headers);
            File.WriteAllBytes(Path.Combine(dir, "SaveGame.dat"), r.Data);
            File.WriteAllBytes(Path.Combine(headers, fileName + ".header"), h);
            return dir;
        }

        static uint BE32(byte[] b, int o)
        {
            return (uint)((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]);
        }

        static void PutBE32(byte[] b, int o, uint v)
        {
            b[o] = (byte)(v >> 24);
            b[o + 1] = (byte)(v >> 16);
            b[o + 2] = (byte)(v >> 8);
            b[o + 3] = (byte)v;
        }

        static int IndexOf(byte[] hay, byte[] needle)
        {
            for (int i = 0; i + needle.Length <= hay.Length; i++)
            {
                if (hay[i] != needle[0]) continue;
                int k = 1;
                while (k < needle.Length && hay[i + k] == needle[k]) k++;
                if (k == needle.Length) return i;
            }
            return -1;
        }
    }
}
