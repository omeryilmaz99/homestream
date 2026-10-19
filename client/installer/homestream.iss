; Inno Setup script for Home Stream (Windows)
#define AppName "Home Stream"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6F1C2B7E-4E0B-4C59-9C1B-3D5A7E9F1A20}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Home Stream
DefaultDirName={autopf}\Home Stream
DefaultGroupName=Home Stream
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=HomeStream-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\HomeStream.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Home Stream"; Filename: "{app}\HomeStream.exe"
Name: "{autodesktop}\Home Stream"; Filename: "{app}\HomeStream.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\HomeStream.exe"; Description: "{cm:LaunchProgram,Home Stream}"; Flags: nowait postinstall skipifsilent
