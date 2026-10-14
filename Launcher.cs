using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

internal static class Launcher
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);

    [STAThread]
    private static int Main(string[] args)
    {
        string temporaryDirectory = null;
        try
        {
            string powerShell = FindPowerShell();
            if (powerShell == null)
                throw new InvalidOperationException(
                    "O PowerShell 7 não foi encontrado. Instale-o em https://aka.ms/powershell e tente novamente.");

            temporaryDirectory = Path.Combine(Path.GetTempPath(), "DiskScope-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temporaryDirectory);

            string scriptPath = Path.Combine(temporaryDirectory, "DiskScope.ps1");
            ExtractResource("DiskScope.ps1", scriptPath);
            ExtractResource("DiskScanner.cs", Path.Combine(temporaryDirectory, "DiskScanner.cs"));
            ExtractResource("PdfReport.ps1", Path.Combine(temporaryDirectory, "PdfReport.ps1"));

            var commandLine = new StringBuilder();
            commandLine.Append("-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File ");
            commandLine.Append(QuoteArgument(scriptPath));
            foreach (string argument in args)
            {
                commandLine.Append(' ');
                commandLine.Append(QuoteArgument(argument));
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = powerShell,
                Arguments = commandLine.ToString(),
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };

            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            MessageBox(IntPtr.Zero, exception.Message, "DiskScope", 0x10);
            return 1;
        }
        finally
        {
            if (!string.IsNullOrEmpty(temporaryDirectory))
            {
                try { Directory.Delete(temporaryDirectory, true); }
                catch { /* O Windows removerá os arquivos temporários posteriormente. */ }
            }
        }
    }

    private static string FindPowerShell()
    {
        string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string standardPath = Path.Combine(programFiles, "PowerShell", "7", "pwsh.exe");
        if (File.Exists(standardPath)) return standardPath;

        string path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (string directory in path.Split(Path.PathSeparator))
        {
            try
            {
                string candidate = Path.Combine(directory.Trim(), "pwsh.exe");
                if (File.Exists(candidate)) return candidate;
            }
            catch { }
        }
        return null;
    }

    private static void ExtractResource(string resourceName, string destination)
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream input = assembly.GetManifestResourceStream(resourceName))
        {
            if (input == null) throw new InvalidOperationException("Recurso interno ausente: " + resourceName);
            using (FileStream output = File.Create(destination)) input.CopyTo(output);
        }
    }

    private static string QuoteArgument(string value)
    {
        if (value == null) return "\"\"";
        return "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }
}
