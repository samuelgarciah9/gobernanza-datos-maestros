# Generar los instaladores (para distribuir a los usuarios)

La app es de escritorio (**PySide6/Qt**). Se distribuye como **instaladores de Windows**
(`Setup.exe`) hechos con Inno Setup, que empaquetan PyInstaller + el Instant Client + el `.env`.
El usuario final **no** necesita Python, ni navegador, ni configurar nada.

Un solo ejecutable con dos modos (`GobernanzaDatosMaestros.exe dashboard` / `... importador`),
pero **dos instaladores separados por rol** que salen del mismo build:

| Instalador | Para quién | Instala |
|---|---|---|
| `Instalar Gobernanza de Datos Maestros …exe` | equipo de gobernanza | solo el **Dashboard** |
| `Instalar Registro de Avance - Gobernanza de Datos …exe` | figuras que registran su avance | solo el **Importador** |

Cada uno tiene su propio `AppId` y carpeta → conviven en la misma máquina y se desinstalan
por separado.

## Requisitos (una vez, en la máquina que compila)

1. **Python 3.13** con las dependencias:
   ```
   pip install -r requirements.txt
   pip install pyinstaller
   ```
2. **Inno Setup 6** (gratis): https://jrsoftware.org/isdl.php
3. El `.env` en la raíz con `ORACLE_CLIENT_LIB_DIR` apuntando a tu Instant Client
   (el build lo copia dentro del paquete).

## Generar (un solo paso)

```
powershell -ExecutionPolicy Bypass -File build\build_installer.ps1
```

Hace: PyInstaller (onedir, **una sola vez**) → copia `instantclient/` y `.env` junto al
`.exe` → Inno Setup compila **los dos** instaladores desde ese mismo paquete.
Quedan en:
```
build\installer_output\Instalar Gobernanza de Datos Maestros 1.0.1.exe
build\installer_output\Instalar Registro de Avance - Gobernanza de Datos 1.0.1.exe
```
Cada archivo (~71 MB) se le pasa al usuario que corresponda (red, USB, correo interno):
el de Gobernanza a los del equipo, el de Registro a las figuras.

## Qué hacen los instaladores

- Instalan por usuario (**sin permisos de administrador**).
- Crean **un** acceso directo en el **Menú Inicio** (Dashboard *o* Importador según el rol)
  y opcionalmente en el escritorio.
- Aparecen en **"Agregar o quitar programas"** con su propio desinstalador.
- Incluyen el `.env` (cuenta Oracle dedicada) → distribuir solo por canales internos.

## Nueva versión

1. Sube `#define MyAppVersion` en `build\installer_common.iss` (una sola vez; lo comparten los dos).
2. Vuelve a compilar. **No cambies los `AppId`** (así Windows los trata como actualización).

## Estructura del código

- `run.py` — punto de entrada (elige ventana por argumento).
- `gd/` — lógica (conexión, datos, exportador, importar, proceso, reporte) + `gd/ui/` (Qt).
- `build/` — `GobernanzaDatosMaestros.spec`, `installer_common.iss`,
  `installer_gobernanza.iss`, `installer_registro.iss`, `build_installer.ps1`.
- `sql/` — DDL y vistas. `legacy/` — versiones Streamlit anteriores (archivadas).
