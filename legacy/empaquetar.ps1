# Genera un ZIP distribuible del proyecto (sin .venv, .env, salidas ni cache).
$ErrorActionPreference = 'Stop'
$root  = $PSScriptRoot
$stage = Join-Path $env:TEMP 'gdm_dist'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }

# Copia todo excepto lo que no debe distribuirse.
# NOTA: el .env SI se incluye a proposito (cuenta Oracle dedicada a proyectos). Uso interno.
robocopy $root $stage /E `
  /XD '.venv' '__pycache__' '.git' '.claude' 'entregables' 'build' `
  /XF '*.pyc' 'GobernanzaDatosMaestros_dist.zip' | Out-Null

# Incluir el Oracle Instant Client (leido de ORACLE_CLIENT_LIB_DIR en .env)
$icDir = $null
$envFile = Join-Path $root '.env'
if (Test-Path $envFile) {
  $line = Select-String -Path $envFile -Pattern '^\s*ORACLE_CLIENT_LIB_DIR\s*=' | Select-Object -First 1
  if ($line) { $icDir = ($line.Line -replace '^\s*ORACLE_CLIENT_LIB_DIR\s*=','').Trim().Trim('"') }
}
if ($icDir -and (Test-Path $icDir)) {
  Write-Host "Incluyendo Instant Client desde: $icDir"
  robocopy $icDir (Join-Path $stage 'instantclient') /E | Out-Null
} else {
  Write-Host "AVISO: no se encontro el Instant Client (ORACLE_CLIENT_LIB_DIR en .env)."
  Write-Host "       El ZIP se generara SIN la carpeta instantclient/ (habra que instalarlo aparte)."
}

# Carpeta entregables vacia (para que exista en destino)
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'entregables') | Out-Null

$zip = Join-Path $root 'GobernanzaDatosMaestros_dist.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
Remove-Item $stage -Recurse -Force
Write-Host ""
Write-Host "Paquete creado: $zip"
