@echo off
setlocal
cd /d "%~dp0"
echo ============================================================
echo   Instalador - Gobernanza de Datos Maestros
echo ============================================================
echo.

REM 1) Verificar Python
where python >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Python no esta instalado o no esta en el PATH.
  echo         Instala Python 3.11 o superior desde:
  echo         https://www.python.org/downloads/
  echo         IMPORTANTE: marca la casilla "Add python.exe to PATH".
  echo.
  pause
  exit /b 1
)

REM 2) Crear entorno virtual aislado (.venv)
if exist ".venv\Scripts\python.exe" (
  echo [OK] El entorno .venv ya existe, se reutiliza.
) else (
  echo [..] Creando entorno virtual .venv ...
  python -m venv .venv
  if errorlevel 1 ( echo [ERROR] No se pudo crear el entorno. & pause & exit /b 1 )
)

REM 3) Instalar dependencias
echo [..] Actualizando pip ...
".venv\Scripts\python.exe" -m pip install --upgrade pip
echo [..] Instalando dependencias (requirements.txt) ...
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 ( echo [ERROR] Fallo la instalacion de dependencias. & pause & exit /b 1 )

echo.
echo ============================================================
echo   Instalacion de librerias COMPLETADA.
echo ============================================================
echo.
echo FALTAN 2 pasos manuales (ver INSTALACION.md):
echo   1) Instalar Oracle Instant Client (modo Thick).
echo   2) Crear el archivo .env (copia .env.example y llena los datos).
echo.
echo Despues, para usar las apps:
echo   - Datos maestros:  doble clic en "Dashboard Gobernanza.bat"
echo   - Figuras:         doble clic en "Importador de decisiones.bat"
echo.
pause
