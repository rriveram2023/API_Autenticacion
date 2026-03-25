$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $PSScriptRoot "conf\app.conf"
$localCandidates = @()
$localDirect = Join-Path $projectRoot "nginx-bin\nginx.exe"
if (Test-Path $localDirect) {
    $localCandidates += $localDirect
}

$localVersioned = Get-ChildItem -Path (Join-Path $projectRoot "nginx-bin") -Filter nginx.exe -Recurse -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName

$candidatePaths = @(
    $localCandidates
    $localVersioned
    "C:\nginx\nginx.exe"
    "C:\Program Files\nginx\nginx.exe"
    "C:\Program Files (x86)\nginx\nginx.exe"
) | Where-Object { $_ }

$nginxExe = $candidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $nginxExe) {
    throw "No se encontro nginx.exe en las rutas esperadas."
}

New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot "logs") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot "temp") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot "temp\client_body_temp") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot "temp\proxy_temp") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot "temp\fastcgi_temp") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot "temp\uwsgi_temp") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot "temp\scgi_temp") | Out-Null

Write-Host "Usando Nginx en: $nginxExe"
Write-Host "Configuracion: $configPath"
$rutaPrefijo = Join-Path $projectRoot "nginx\"
$rutaPid = Join-Path $PSScriptRoot "logs\nginx.pid"

if (Test-Path $rutaPid) {
    $pidExistente = (Get-Content $rutaPid -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    $procesoActivo = $null
    if ($pidExistente -match '^\d+$') {
        $procesoActivo = Get-Process -Id ([int]$pidExistente) -ErrorAction SilentlyContinue
    }

    if ($procesoActivo) {
        Write-Host "Recargando Nginx existente"
        & $nginxExe -p $rutaPrefijo -c $configPath -s reload
    } else {
        Write-Host "PID huerfano detectado en nginx.pid; se eliminara y se levantara Nginx nuevo"
        Remove-Item $rutaPid -Force -ErrorAction SilentlyContinue
        Write-Host "Levantando Nginx nuevo"
        & $nginxExe -p $rutaPrefijo -c $configPath
    }
} else {
    Write-Host "Levantando Nginx nuevo"
    & $nginxExe -p $rutaPrefijo -c $configPath
}
