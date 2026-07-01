param (
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"
$ProjectDir = $PSScriptRoot
$BuildDir = Join-Path $ProjectDir "builds\windows"
$ZipName = "Pixbots-G-Release-$Version.zip"
$ZipPath = Join-Path $ProjectDir "builds\$ZipName"

Write-Host "🔧 Preparing build directory..." -ForegroundColor Cyan
if (!(Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
} else {
    Remove-Item -Path "$BuildDir\*" -Force -Recurse
}

Write-Host "🔨 Building Pixbots-G (Windows Desktop)..." -ForegroundColor Cyan
# Godot CLI export. Ensure 'godot' is in your PATH.
# This will output Pixbots-G.exe and Pixbots-G.console.exe based on Godot's Windows export behavior.
Start-Process -FilePath "godot" -ArgumentList "--headless", "--export-release", "`"Windows Desktop`"" -NoNewWindow -Wait

Write-Host "📦 Packaging Release ZIP..." -ForegroundColor Cyan
# Collect the files we want to zip (.exe, .console.exe, and .pck if exported separately)
$FilesToZip = Get-ChildItem -Path $BuildDir | Where-Object { 
    $_.Extension -eq ".exe" -or $_.Extension -eq ".pck" 
}

if ($FilesToZip.Count -eq 0) {
    Write-Host "❌ Build failed! No executables found in $BuildDir" -ForegroundColor Red
    exit 1
}

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Compress-Archive -Path $FilesToZip.FullName -DestinationPath $ZipPath -Force

Write-Host "✅ Build and Package Complete!" -ForegroundColor Green
Write-Host "Release ZIP located at: $ZipPath" -ForegroundColor Green

# ---------------------------------------------------------
# OPTIONAL AUTO-UPLOAD (e.g., GitHub Releases using gh CLI)
# ---------------------------------------------------------
# If you want to automatically upload this to a GitHub release:
# Write-Host "🚀 Uploading to GitHub Releases..." -ForegroundColor Cyan
# gh release create $Version $ZipPath --title "Release $Version" --notes "Automated release build."
