$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Pixbots-G Installer Generation Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Compile Dialogues
Write-Host "`n--- 1. Compiling Dialogue & Monologues ---" -ForegroundColor Yellow
python compile_dialogue.py
python inject_monologues.py

# 2. Build Rust Extension
Write-Host "`n--- 2. Building Rust GDExtension ---" -ForegroundColor Yellow
if (Test-Path "rust_ext") {
    Push-Location rust_ext
    cargo build --release
    Pop-Location
} else {
    Write-Host "[WARNING] rust_ext directory not found!" -ForegroundColor Red
}

# 3. Export Godot Project
Write-Host "`n--- 3. Exporting Godot Project ---" -ForegroundColor Yellow
$GodotExe = "Godot_v4.6.3-stable_win64.exe"
if (!(Test-Path $GodotExe)) {
    Write-Host "[ERROR] Godot executable not found! Make sure $GodotExe is in this folder." -ForegroundColor Red
    exit 1
}

$BuildDir = "builds\windows"
if (!(Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
} else {
    Remove-Item -Path "$BuildDir\*" -Force -Recurse
}

# Run Godot export
Start-Process -FilePath ".\$GodotExe" -ArgumentList "--headless", "--export-release", "`"Windows Desktop`"" -NoNewWindow -Wait

# Verify export
$ExportedExe = Join-Path $BuildDir "Pixbots-G-2026-07-14.exe"
if (!(Test-Path $ExportedExe)) {
    $ExportedExe = Get-ChildItem $BuildDir -Filter "*.exe" | Select-Object -ExpandProperty FullName -First 1
}

if (!(Test-Path $ExportedExe)) {
    Write-Host "[ERROR] Godot export failed! No executable found in $BuildDir" -ForegroundColor Red
    exit 1
}

Write-Host "`n--- 4. Preparing Files for Packaging ---" -ForegroundColor Yellow
# Rename the exported exe to something cleaner
$FinalExePath = Join-Path $BuildDir "Pixbots-G.exe"
if ($ExportedExe -ne $FinalExePath) {
    Rename-Item -Path $ExportedExe -NewName "Pixbots-G.exe"
    $ExportedExe = $FinalExePath
}

# Copy the Rust DLL into the export directory if it exists
# (GDExtensions usually expect to be in the same relative path as the project)
# Godot 4 exports .dlls automatically if they are referenced by a .gdextension file, 
# but let's double check what's in the build dir.
$FilesToPackage = Get-ChildItem -Path $BuildDir -File

# 5. Generate C# Installer
Write-Host "`n--- 5. Generating Installer ---" -ForegroundColor Yellow
.\build_csharp_installer.ps1
