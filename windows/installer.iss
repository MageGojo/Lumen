; Inno Setup script for Lumen (Windows installer).
; Compiled in CI by ISCC.exe against the release build output.

#define MyAppName "Lumen"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "apizero.cn"
#define MyAppURL "https://github.com/MageGojo/Lumen"
#define MyAppExeName "lumen.exe"

[Setup]
; The script lives in windows/, but the Flutter build output and the dist/
; folder are at the repository root. Resolve all relative paths (the [Files]
; Source below and OutputDir) from the repo root instead of windows/.
SourceDir=..
AppId={{8F4A2E10-9C3B-4D7E-A1F6-2B5C9D0E7A33}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
DefaultDirName={autopf}\Lumen
DefaultGroupName=Lumen
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=Lumen-Windows-Setup
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
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Lumen"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,Lumen}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Lumen"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,Lumen}"; Flags: nowait postinstall skipifsilent
