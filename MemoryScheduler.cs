using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class MemoryScheduler
{
    private static readonly string Launcher = Path.Combine(
        AppDomain.CurrentDomain.BaseDirectory, "Plain Craft Launcher 2.exe");
    private const int IntervalMs = 300000;
    private static readonly string LogDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PCLMemoryScheduler");

    [StructLayout(LayoutKind.Sequential)]
    private sealed class MemoryStatus
    {
        public uint Length = (uint)Marshal.SizeOf(typeof(MemoryStatus));
        public uint Load;
        public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile;
        public ulong TotalVirtual, AvailableVirtual, AvailableExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx([In, Out] MemoryStatus status);

    private static long AvailableMiB()
    {
        var status = new MemoryStatus();
        return GlobalMemoryStatusEx(status) ? (long)(status.AvailablePhysical / 1048576) : -1;
    }

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            if (args.Length == 1 && args[0] == "--once") return Optimize();
            if (args.Length != 0) return 2;
            bool created;
            using (var mutex = new Mutex(true, @"Global\PCLMemoryScheduler", out created))
            {
                if (!created) return 0;
                while (true)
                {
                    var timer = Stopwatch.StartNew();
                    Optimize();
                    int remaining = IntervalMs - (int)Math.Min(timer.ElapsedMilliseconds, IntervalMs);
                    if (remaining > 0) Thread.Sleep(remaining);
                }
            }
        }
        catch { return 1; }
    }

    private static int Optimize()
    {
        var started = DateTimeOffset.Now;
        long before = AvailableMiB();
        string result = "error", detail = "";
        int? exitCode = null;
        try
        {
            var info = new ProcessStartInfo(Launcher, "--memory")
            {
                WorkingDirectory = Path.GetDirectoryName(Launcher),
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            using (var process = Process.Start(info))
            {
                if (!process.WaitForExit(90000))
                {
                    process.Kill();
                    process.WaitForExit(5000);
                    result = "timeout";
                    detail = "PCL did not exit within 90 seconds; this invocation was stopped.";
                }
                else
                {
                    exitCode = process.ExitCode;
                    if (exitCode >= 0)
                    {
                        result = "success";
                        detail = "PCL reported reclaimed KiB: " + exitCode;
                    }
                    else detail = "PCL returned an error code.";
                }
            }
        }
        catch (Exception ex) { detail = ex.GetType().Name + ": " + ex.Message; }

        try
        {
            Directory.CreateDirectory(LogDirectory);
            var log = Path.Combine(LogDirectory, "runs.csv");
            if (File.Exists(log) && new FileInfo(log).Length > 1048576)
            {
                var previous = log + ".previous";
                if (File.Exists(previous)) File.Delete(previous);
                File.Move(log, previous);
            }
            if (!File.Exists(log)) File.WriteAllText(log,
                "started,finished,result,pcl_exit_code,available_before_mib,available_after_mib,detail\r\n", Encoding.UTF8);
            string line = Csv(started.ToString("o")) + "," + Csv(DateTimeOffset.Now.ToString("o")) + "," +
                Csv(result) + "," + (exitCode.HasValue ? exitCode.Value.ToString(CultureInfo.InvariantCulture) : "") +
                "," + before + "," + AvailableMiB() + "," + Csv(detail) + "\r\n";
            File.AppendAllText(log, line, Encoding.UTF8);
        }
        catch { return 1; }
        return result == "success" ? 0 : 1;
    }

    private static string Csv(string value) { return "\"" + value.Replace("\"", "\"\"") + "\""; }
}
