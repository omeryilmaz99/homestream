; Inno Setup script for Home Dosya (Windows)
#define AppName "Home Dosya"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{A3D58E21-7C4B-4F6E-B2A9-5E81C0D4F713}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Home Dosya
DefaultDirName={autopf}\Home Dosya
DefaultGroupName=Home Dosya
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=HomeDosya-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\HomeDosya.exe
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
Name: "{group}\Home Dosya"; Filename: "{app}\HomeDosya.exe"
Name: "{autodesktop}\Home Dosya"; Filename: "{app}\HomeDosya.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\HomeDosya.exe"; Description: "{cm:LaunchProgram,Home Dosya}"; Flags: nowait postinstall skipifsilent
