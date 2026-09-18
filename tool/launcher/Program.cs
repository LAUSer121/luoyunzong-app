// 落云宗 · 宗门管理 —— 便携版单文件启动器
//
// 结构：[本启动器 exe] + [标记] + [Flutter 发布目录的 zip 载荷]
// 行为：首次运行把载荷解压到目标目录，然后启动 luoyunzong.exe；
//       数据目录固定为 <目标目录>/data，因此整个文件夹可以随身携带。
//
// 参数：--extract-only   只解压不启动（用于构建期自检）
//       --print-target   只打印目标目录
// 环境变量：LUOYUNZONG_DIR（解压目录）、LUOYUNZONG_DATA_DIR（数据目录）

using System.Diagnostics;
using System.IO.Compression;
using System.Security.Cryptography;

const string Marker = "<<<LUOYUNZONG_PAYLOAD_V1>>>";
const string AppExe = "luoyunzong.exe";
const string HashFile = ".payload.sha256";

string self = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule?.FileName
    ?? throw new InvalidOperationException("无法定位自身可执行文件");

bool extractOnly = args.Contains("--extract-only");
bool printTargetOnly = args.Contains("--print-target");

string target = ResolveTarget(Environment.GetEnvironmentVariable("LUOYUNZONG_DIR"), self);
if (printTargetOnly)
{
    Console.WriteLine(target);
    return 0;
}

long offset = FindPayloadOffset(self);
if (offset < 0)
{
    Console.Error.WriteLine("[portable] 载荷缺失：文件可能被截断或复制不完整。");
    return 2;
}

Directory.CreateDirectory(target);
string appPath = Path.Combine(target, AppExe);
string hashPath = Path.Combine(target, HashFile);
string payloadHash = HashRange(self, offset);

bool upToDate = File.Exists(appPath)
    && File.Exists(hashPath)
    && string.Equals(File.ReadAllText(hashPath).Trim(), payloadHash, StringComparison.OrdinalIgnoreCase);

if (!upToDate)
{
    Console.WriteLine($"[portable] 首次运行/版本更新，正在解压到：{target}");
    string tempZip = Path.Combine(Path.GetTempPath(), "luoyunzong-" + Guid.NewGuid().ToString("N") + ".zip");
    try
    {
        CopyRange(self, offset, tempZip);
        ZipFile.ExtractToDirectory(tempZip, target, overwriteFiles: true);
        File.WriteAllText(hashPath, payloadHash);
    }
    finally
    {
        try { if (File.Exists(tempZip)) File.Delete(tempZip); } catch { /* 忽略 */ }
    }
}

if (!File.Exists(appPath))
{
    Console.Error.WriteLine($"[portable] 解压结果缺少 {AppExe}，无法启动。");
    return 3;
}

if (extractOnly)
{
    Console.WriteLine($"[portable] 已解压到：{target}");
    return 0;
}

string dataDir = Environment.GetEnvironmentVariable("LUOYUNZONG_DATA_DIR")
    ?? Path.Combine(target, "data");
Directory.CreateDirectory(dataDir);

var startInfo = new ProcessStartInfo(appPath)
{
    WorkingDirectory = target,
    UseShellExecute = false,
};
startInfo.Environment["LUOYUNZONG_DATA_DIR"] = dataDir;

Process.Start(startInfo);
return 0;

// ---------------------------------------------------------------------------

static string ResolveTarget(string? fromEnv, string selfPath)
{
    if (!string.IsNullOrWhiteSpace(fromEnv))
    {
        return Path.GetFullPath(fromEnv!);
    }

    string exeDir = Path.GetDirectoryName(Path.GetFullPath(selfPath)) ?? Directory.GetCurrentDirectory();
    string beside = Path.Combine(exeDir, "luoyunzong-app");
    try
    {
        Directory.CreateDirectory(beside);
        string probe = Path.Combine(beside, ".writable");
        File.WriteAllText(probe, "1");
        File.Delete(probe);
        return beside;
    }
    catch
    {
        // exe 所在目录不可写（例如放在只读位置）：退回用户目录
    }

    return Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Luoyunzong",
        "app");
}

static long FindPayloadOffset(string selfPath)
{
    using FileStream fs = File.OpenRead(selfPath);
    const int window = 512 * 1024;
    long start = Math.Max(0, fs.Length - window);
    int size = (int)(fs.Length - start);
    byte[] buffer = new byte[size];
    fs.Position = start;
    fs.ReadExactly(buffer, 0, size);

    byte[] marker = System.Text.Encoding.ASCII.GetBytes(Marker);
    for (int i = buffer.Length - marker.Length; i >= 0; i--)
    {
        bool match = true;
        for (int j = 0; j < marker.Length; j++)
        {
            if (buffer[i + j] != marker[j])
            {
                match = false;
                break;
            }
        }
        if (match)
        {
            return start + i + marker.Length;
        }
    }
    return -1;
}

static string HashRange(string selfPath, long offset)
{
    using FileStream fs = File.OpenRead(selfPath);
    fs.Position = offset;
    using SHA256 sha = SHA256.Create();
    byte[] hash = sha.ComputeHash(fs);
    return Convert.ToHexString(hash);
}

static void CopyRange(string selfPath, long offset, string destination)
{
    using FileStream src = File.OpenRead(selfPath);
    src.Position = offset;
    using FileStream dst = File.Create(destination);
    src.CopyTo(dst);
}
