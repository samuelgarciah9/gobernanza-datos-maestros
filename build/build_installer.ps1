# Compila la app con PyInstaller (onedir), le agrega el Instant Client y el .env,
# y genera el instalador con Inno Setup. Todo en un paso.
# Uso:  powershell -ExecutionPolicy Bypass -File build\build_installer.ps1
$ErrorActionPreference = "Stop"
$build = $PSScriptRoot
$proj  = Split-Path $build -Parent

Write-Host "==> 1/3  Empaquetando con PyInstaller (onedir)..." -ForegroundColor Cyan
Set-Location $proj
# Limpia caches para evitar reusar un exe viejo.
Remove-Item -Recurse -Force "build\dist","build\work" -ErrorAction SilentlyContinue
python -m PyInstaller --noconfirm --distpath "build\dist" --workpath "build\work" `
    "build\GobernanzaDatosMaestros.spec"

$dest = Join-Path $proj "build\dist\GobernanzaDatosMaestros"
if (-not (Test-Path (Join-Path $dest "GobernanzaDatosMaestros.exe"))) {
    Write-Host "PyInstaller no genero el ejecutable." -ForegroundColor Red; exit 1
}

Write-Host "==> 2/3  Agregando Instant Client y .env junto al .exe..." -ForegroundColor Cyan
$icDir = $null
$envFile = Join-Path $proj ".env"
if (Test-Path $envFile) {
    $l = Select-String -Path $envFile -Pattern '^\s*ORACLE_CLIENT_LIB_DIR\s*=' | Select-Object -First 1
    if ($l) { $icDir = ($l.Line -replace '^\s*ORACLE_CLIENT_LIB_DIR\s*=','').Trim().Trim('"') }
}
if ($icDir -and (Test-Path $icDir)) {
    robocopy $icDir (Join-Path $dest "instantclient") /E | Out-Null
    Write-Host "    Instant Client incluido desde: $icDir"
} else {
    Write-Host "    AVISO: sin Instant Client (ORACLE_CLIENT_LIB_DIR)." -ForegroundColor Yellow
}
Copy-Item $envFile (Join-Path $dest ".env") -Force
New-Item -ItemType Directory -Force -Path (Join-Path $dest "entregables") | Out-Null

Write-Host "==> 3/3  Compilando los DOS instaladores con Inno Setup..." -ForegroundColor Cyan
$iscc = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { Write-Host "Inno Setup no encontrado." -ForegroundColor Yellow; exit 1 }
Set-Location $build
# Mismo onedir, dos instaladores: uno para el equipo de gobernanza (Dashboard),
# otro para las figuras que solo registran su avance (Importador).
& $iscc "installer_gobernanza.iss"
& $iscc "installer_registro.iss"
Write-Host "`nListo. Instaladores en:  build\installer_output\" -ForegroundColor Green
Write-Host "    - Instalar Gobernanza de Datos Maestros 1.0.1.exe      (equipo de gobernanza / Dashboard)"
Write-Host "    - Instalar Registro de Avance - Gobernanza de Datos 1.0.1.exe  (figuras / Importador)"
