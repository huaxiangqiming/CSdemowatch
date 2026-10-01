#ifndef AppVersion
  #define AppVersion "0.9.2-beta.1"
#endif
#ifndef PackageRoot
  #define PackageRoot "..\dist\windows"
#endif
#ifndef ReleaseDir
  #define ReleaseDir "..\dist\releases"
#endif
#ifndef ArtifactSuffix
  #define ArtifactSuffix ""
#endif
#ifndef VersionInfo
  #define VersionInfo "0.9.2.0"
#endif
[Setup]
#ifdef SignedRelease
SignTool=cs2trusted
SignedUninstaller=yes
#endif
AppId={{90737B99-1704-428F-9D37-5CC0F7B13869}
AppName=CS2 Tactical Replay
AppVersion={#AppVersion}
AppPublisher=huaxiangqiming
AppPublisherURL=https://github.com/huaxiangqiming/CSdemowatch
AppSupportURL=https://github.com/huaxiangqiming/CSdemowatch/issues
AppUpdatesURL=https://github.com/huaxiangqiming/CSdemowatch/releases
DefaultDirName={localappdata}\Programs\CS2TacticalReplay
DefaultGroupName=CS2 Tactical Replay
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#ReleaseDir}
OutputBaseFilename=CS2TacticalReplay-{#AppVersion}-windows-x64-setup{#ArtifactSuffix}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\CS2TacticalReplay.exe
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#VersionInfo}
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
[Files]
Source: "{#PackageRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\CS2 Tactical Replay"; Filename: "{app}\CS2TacticalReplay.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\CS2 Tactical Replay"; Filename: "{app}\CS2TacticalReplay.exe"; WorkingDir: "{app}"; Tasks: desktopicon
[Run]
Filename: "{app}\CS2TacticalReplay.exe"; Description: "{cm:LaunchProgram,CS2 Tactical Replay}"; Flags: nowait postinstall skipifsilent
; User demos, settings and caches are outside {app} and are intentionally retained.
