$ErrorActionPreference = "Stop"
$BuildDir = "builds\windows"
$ZipPath = "Pixbots-G-Release.zip"
$InstallerExe = "Pixbots-Installer.exe"

# 1. Zip the build directory
Write-Host "Zipping build directory..."
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path "$BuildDir\*" -DestinationPath $ZipPath -Force

# 2. Write C# Source
$CsSource = @"
using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Diagnostics;

class Program
{
    static void Main(string[] args)
    {
        try
        {
            Console.WriteLine("Installing Pixbots-G...");
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            string targetDir = Path.Combine(desktop, "Pixbots-G");
            
            if (!Directory.Exists(targetDir))
            {
                Directory.CreateDirectory(targetDir);
            }

            // Extract the embedded zip
            Assembly currentAssembly = Assembly.GetExecutingAssembly();
            using (Stream resourceStream = currentAssembly.GetManifestResourceStream("Pixbots-G-Release.zip"))
            {
                if (resourceStream == null)
                {
                    Console.WriteLine("Error: Could not find embedded game data.");
                    Console.ReadLine();
                    return;
                }

                using (ZipArchive archive = new ZipArchive(resourceStream, ZipArchiveMode.Read))
                {
                    foreach (ZipArchiveEntry entry in archive.Entries)
                    {
                        string destinationPath = Path.Combine(targetDir, entry.FullName);
                        string destinationDir = Path.GetDirectoryName(destinationPath);
                        
                        if (!Directory.Exists(destinationDir))
                        {
                            Directory.CreateDirectory(destinationDir);
                        }
                        
                        if (entry.Name != "")
                        {
                            entry.ExtractToFile(destinationPath, true);
                        }
                    }
                }
            }

            Console.WriteLine("Installed successfully to " + targetDir);
            
            // Run the game
            string exePath = Path.Combine(targetDir, "Pixbots-G.exe");
            if (File.Exists(exePath))
            {
                Process.Start(new ProcessStartInfo()
                {
                    FileName = exePath,
                    WorkingDirectory = targetDir,
                    UseShellExecute = true
                });
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("Installation failed: " + ex.Message);
            Console.ReadLine();
        }
    }
}
"@

Set-Content -Path "Installer.cs" -Value $CsSource

# 3. Compile the C# source and embed the zip
Write-Host "Compiling installer..."
$CscPath = "$env:windir\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (!(Test-Path $CscPath)) {
    $CscPath = "$env:windir\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}

$compileArgs = @(
    "/target:exe",
    "/out:$InstallerExe",
    "/resource:$ZipPath",
    "/reference:System.IO.Compression.dll",
    "/reference:System.IO.Compression.FileSystem.dll",
    "Installer.cs"
)

$proc = Start-Process -FilePath $CscPath -ArgumentList $compileArgs -NoNewWindow -PassThru -Wait
if ($proc.ExitCode -eq 0) {
    Write-Host "Successfully generated $InstallerExe" -ForegroundColor Green
} else {
    Write-Host "Compilation failed with code $($proc.ExitCode)" -ForegroundColor Red
}

# Cleanup
Remove-Item "Installer.cs" -Force
Remove-Item $ZipPath -Force

