@echo off
REM Crea el ZIP distribuible del proyecto (GobernanzaDatosMaestros_dist.zip).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "empaquetar.ps1"
pause
