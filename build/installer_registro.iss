; Instalador para las FIGURAS que solo registran su avance: instala SOLO el
; Importador de Decisiones (carga su Excel de captura a la base). AppId y carpeta
; propios para que conviva con el instalador de Gobernanza en la misma maquina.
; El resto de la config vive en installer_common.iss.
#define MyAppName      "Registro de Avance - Gobernanza de Datos"
#define MyAppId        "{{C3F8C1D5-4A6B-5E3F-AB2D-8F7A3E9B5D21}"
#define MyDirName      "Registro de Avance Gobernanza"
#define MyShortcutName "Importador de Decisiones (Figuras)"
#define MyMode         "importador"
#include "installer_common.iss"
