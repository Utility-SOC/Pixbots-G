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
# The console variant, not the windowed Godot_v4.6.3-stable_win64.exe - the
# windowed exe does not reliably block the calling process for headless CLI
# invocations (confirmed by hand: the call operator returned in ~6ms with no
# process left running and no exit code set), which let the warm-up pass
# below race against the real export pass that follows it, corrupting both.
# The console exe blocks and reports a real exit code, same as every
# headless test run in this project already relies on.
$GodotExe = "Godot_v4.6.3-stable_win64_console.exe"
if (!(Test-Path $GodotExe)) {
    Write-Host "[ERROR] Godot executable not found! Make sure $GodotExe is in this folder." -ForegroundColor Red
    exit 1
}

# Warm-up pass: a completely fresh checkout (every CI run, and .godot/ is
# gitignored) has no global script-class cache yet. The FIRST headless
# Godot launch after that builds it but can bail mid-scan with cascading
# "Identifier X not declared" errors across every class_name script -
# confirmed by hand this session (a `--headless --quit` pass alone wasn't
# enough to force the full rebuild; `--editor` is required to actually
# trigger the EditorFileSystem project scan headlessly). Without this, the
# real export below risks failing outright, or worse, silently shipping a
# build where autoloads never finished loading.
Write-Host "Warming up the script-class cache (first launch after a fresh checkout)..." -ForegroundColor DarkGray
& ".\$GodotExe" --headless --editor --quit
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARNING] Cache warm-up pass exited with code $LASTEXITCODE - continuing, but watch the export step below for cascading class errors." -ForegroundColor Yellow
}

$BuildDir = "builds\windows"
if (!(Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
} else {
    Remove-Item -Path "$BuildDir\*" -Force -Recurse
}

# Run Godot export. Call operator (&), not Start-Process -ArgumentList - the
# latter's array-of-strings quoting mangled the "Windows Desktop" preset
# name (embedded space) unreliably; & passes it through cleanly. -PassThru
# equivalent for exit code: $LASTEXITCODE after a call-operator invocation.
& ".\$GodotExe" --headless --export-release "Windows Desktop"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Godot export process exited with code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

# Verify export
$ExportedExe = Join-Path $BuildDir "Pixbots-G-2026-07-14.exe"
if (!(Test-Path $ExportedExe)) {
    $Found = Get-ChildItem $BuildDir -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -First 1
    $ExportedExe = if ($Found) { $Found } else { $null }
}

if (!$ExportedExe -or !(Test-Path $ExportedExe)) {
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

# 5. Generate Installer (Inno Setup - real Start Menu/Desktop shortcuts,
# Add/Remove Programs uninstall entry, chosen install directory. Replaces
# the old build_csharp_installer.ps1 zip-extractor stub.)
Write-Host "`n--- 5. Generating Installer ---" -ForegroundColor Yellow
$ISCC = "ISCC.exe"
$IsccCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$IsccPath = Get-Command $ISCC -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (!$IsccPath) {
    foreach ($candidate in $IsccCandidates) {
        if (Test-Path $candidate) {
            $IsccPath = $candidate
            break
        }
    }
}
if (!$IsccPath) {
    Write-Host "[ERROR] Inno Setup's ISCC.exe not found. Install Inno Setup (https://jrsoftware.org/isinfo.php) or, on CI, add the Inno Setup provisioning step to the workflow." -ForegroundColor Red
    exit 1
}

# Version from the pushed git tag when one points at HEAD (CI release
# builds), otherwise the .iss script's own "1.0.0" default (local dev
# builds off a tag-less checkout). The common case (no exact tag) makes
# git write to stderr, which $ErrorActionPreference = "Stop" (set at the
# top of this script) turns into a terminating NativeCommandError - swap
# to SilentlyContinue just for this call so a tag-less checkout doesn't
# abort the whole build.
$VersionArgs = @()
$PrevEAP = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
$GitTag = git describe --tags --exact-match 2>$null
$ErrorActionPreference = $PrevEAP
if ($LASTEXITCODE -eq 0 -and $GitTag) {
    $VersionNumber = $GitTag -replace '^v', ''
    Write-Host "Building installer version $VersionNumber (from tag $GitTag)" -ForegroundColor DarkGray
    $VersionArgs = @("/DMyAppVersion=$VersionNumber")
}

& $IsccPath $VersionArgs "installer\pixbots.iss"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Inno Setup compilation failed with code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}
Write-Host "Successfully generated Pixbots-Installer.exe" -ForegroundColor Green
