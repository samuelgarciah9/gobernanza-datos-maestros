; Instalador para el EQUIPO DE GOBERNANZA: instala SOLO el Dashboard de Datos
; Maestros (foto/excels/reporte/refresh). El resto de la config vive en
; installer_common.iss. Se compila desde build\build_installer.ps1.
#define MyAppName      "Gobernanza de Datos Maestros"
#define MyAppId        "{{B2E7B0C4-3F5A-4D2E-9A1C-7E6F2D8A4C10}"
#define MyDirName      "Gobernanza de Datos Maestros"
#define MyShortcutName "Dashboard Gobernanza (Datos Maestros)"
#define MyMode         "dashboard"
#include "installer_common.iss"
