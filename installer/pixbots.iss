; Real Windows installer for Pixbots-G (task #15 - replaces the old
; build_csharp_installer.ps1 hand-rolled extractor, which had no Start Menu
; shortcut, no uninstaller/Add-Remove-Programs entry, no chosen install
; directory, and no version metadata). Compiled via Inno Setup's ISCC.exe,
; invoked from build_installer.ps1.
;
; MyAppVersion can be overridden at compile time from CI (derived from the
; pushed git tag) via: ISCC /DMyAppVersion=1.2.3 installer\pixbots.iss
#ifndef MyAppVersion
  #define MyAppVersion "1.1.0"
#endif
#define MyAppName "Pixbots-G"
#define MyAppExeName "Pixbots-G.exe"
#define MyAppPublisher "Utility-SOC"

[Setup]
AppId={{6C6F2C6A-6F6F-4B57-9E7A-8B6A9C4F3D21}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; No admin rights required - installs per-user, same convention as
; VSCode/Discord-style modern installers. {autopf} resolves to
; {localappdata}\Programs when PrivilegesRequired is "lowest".
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline dialog
DisableProgramGroupPage=yes
; Real uninstaller entry in Add/Remove Programs - the whole point of
; replacing the old zip-extractor stub.
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=..
OutputBaseFilename=Pixbots-Installer
SetupIconFile=..\icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Whole exported build directory (exe + embedded .pck + any loose Rust
; GDExtension DLLs Godot's export copied alongside it), recursive.
Source: "..\builds\windows\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Official Microsoft VC++ 2015-2022 x64 Redistributable (rust_ext.dll
; dynamically links this - task #15 follow-up: "does it prompt to install
; the VC++?" it didn't, this closes that gap). Bundled rather than
; downloaded at install time - works offline, no extra visible step for
; the player. `dontcopy` means it's staged into {tmp} for [Run] to execute
; conditionally below, not installed into {app} permanently.
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: dontcopy

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Silent, unattended, skipped entirely when the registry check below says
; the runtime is already present (the common case - lots of software
; already installs it) - the player never sees this happen.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing prerequisites..."; Check: VCRedistNeedsInstall; Flags: waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// VC++ 2015/2017/2019/2022 all share one ABI-compatible runtime tracked
// under this same "14.0" versioned key regardless of which VS version
// actually installed it - the standard check every VC++-bundling Inno
// Setup script uses. Installed=1 means present; anything else (missing
// key, missing value, or a value that isn't 1) means we need to run the
// bundled redistributable.
function VCRedistNeedsInstall(): Boolean;
var
  Version: Cardinal;
begin
  Result := True;
  if RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64', 'Installed', Version) then
  begin
    if Version = 1 then
      Result := False;
  end;
end;
