; Cuerpo compartido por los DOS instaladores de Gobernanza de Datos Maestros:
;   installer_gobernanza.iss  -> equipo de gobernanza (solo Dashboard)
;   installer_registro.iss    -> figuras que registran su avance (solo Importador)
; Cada uno define sus propias variables (MyAppName, MyAppId, MyDirName,
; MyShortcutName, MyMode) y luego incluye este archivo con #include.
; Ambos usan el MISMO onedir de PyInstaller: build\dist\GobernanzaDatosMaestros\
; (exe + _internal + instantclient + .env). Lo genera build\build_installer.ps1.

#define MyAppVersion "1.0.1"
#define MyAppPublisher "Data Governance Portfolio"
#define MyAppExe "GobernanzaDatosMaestros.exe"
#define MyAppFolder "GobernanzaDatosMaestros"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyDirName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=installer_output
OutputBaseFilename=Instalar {#MyAppName} {#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Toda la carpeta onedir (exe + _internal + instantclient + .env). Es la misma
; para los dos instaladores; solo cambian los accesos directos de abajo.
Source: "dist\{#MyAppFolder}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyShortcutName}";        Filename: "{app}\{#MyAppExe}"; Parameters: "{#MyMode}"; WorkingDir: "{app}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyShortcutName}";  Filename: "{app}\{#MyAppExe}"; Parameters: "{#MyMode}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Parameters: "{#MyMode}"; Description: "Abrir {#MyShortcutName}"; Flags: nowait postinstall skipifsilent
