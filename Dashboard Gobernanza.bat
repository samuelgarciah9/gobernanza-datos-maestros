@echo off
REM Lanzador de DESARROLLO del Dashboard (requiere Python + requirements.txt).
REM Los usuarios finales lo abren con el acceso directo que crea el instalador.
cd /d "%~dp0"

REM Elegir un Python REAL. Evita el stub de Microsoft Store (WindowsApps\python.exe
REM = AppInstallerPythonRedirector.exe), que NO corre la app y se cierra al instante.
set "PYEXE="
if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" set "PYEXE=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
if not defined PYEXE if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PYEXE=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PYEXE (
    where py >nul 2>&1 && set "PYEXE=py"
)
if not defined PYEXE set "PYEXE=python"

echo Usando Python: %PYEXE%
"%PYEXE%" run.py dashboard

REM Si algo falla al arrancar, deja la consola abierta para leer el error.
if errorlevel 1 (
    echo.
    echo *** El dashboard termino con error ^(codigo %errorlevel%^). Revisa el mensaje de arriba. ***
    pause
)
