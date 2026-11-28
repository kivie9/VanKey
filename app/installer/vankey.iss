; Bộ cài VanKey cho Windows (Inno Setup 6).
; Build:  iscc /DAppVersion=1.2.3 installer\vankey.iss   (chạy trong thư mục app, sau `flutter build windows --release`)
; Ra file: build\installer\vankey-<phiên bản>-windows-setup.exe
;
; - Cài riêng cho người dùng hiện tại (%LOCALAPPDATA%\Programs\VanKey), không cần quyền admin.
; - Kho dữ liệu nằm ở %APPDATA%\com.vankey\vankey, không nằm trong thư mục cài: gỡ app không xóa kho.
; - Cài im lặng (Microsoft Store dùng): vankey-...-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

#define AppName "VanKey"
#define AppExe "vankey.exe"
#define AppUrl "https://github.com/kivie9/VanKey"

[Setup]
; AppId cố định mãi mãi: nhờ nó bản mới cài đè lên bản cũ thay vì cài thành app thứ hai.
AppId={{B3C0B278-B51F-42A3-A3DD-124B0FCF875C}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Windows 10 1809 trở lên (giới hạn của Flutter).
MinVersion=10.0.17763
OutputDir=..\build\installer
OutputBaseFilename=vankey-{#AppVersion}-windows-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Đang mở VanKey thì đóng lại trước khi chép đè.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
; Các lựa chọn hiện ở trang "Select Additional Tasks" khi cài. Inno nhớ lựa chọn cũ khi cài đè bản mới.
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "Start {#AppName} when Windows starts"; GroupDescription: "Other options:"; Flags: unchecked

[Registry]
; Tự chạy cùng Windows (chỉ người dùng hiện tại). Gỡ app thì xóa luôn mục này.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\{#AppExe}"""; Flags: uninsdeletevalue; Tasks: autostart

[InstallDelete]
; Tài nguyên của bản cũ: xóa trước để không sót tệp thừa khi cài đè.
Type: filesandordirs; Name: "{app}\data\flutter_assets"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
