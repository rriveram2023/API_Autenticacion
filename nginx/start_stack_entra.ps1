$ErrorActionPreference = "Stop"

$rutaProyecto = Split-Path -Parent $PSScriptRoot
$rutaAuthApi = Join-Path $PSScriptRoot "start_auth_api.ps1"
$rutaApiSegura = Join-Path $PSScriptRoot "start_api_proxy.ps1"
$rutaOauth = Join-Path $PSScriptRoot "start_oauth2_proxy.ps1"
$rutaNginx = Join-Path $PSScriptRoot "start_nginx.ps1"
$rutaEnv = Join-Path $rutaProyecto ".env"

function Obtener-Variables-Env {
    param([string]$RutaArchivo)

    $resultado = @{}
    if (-not (Test-Path $RutaArchivo)) {
        return $resultado
    }

    foreach ($linea in Get-Content -Path $RutaArchivo) {
        $contenido = $linea.Trim()
        if (-not $contenido -or $contenido.StartsWith("#") -or -not $contenido.Contains("=")) {
            continue
        }
        $partes = $contenido.Split("=", 2)
        $resultado[$partes[0].Trim()] = $partes[1].Trim().Trim('"').Trim("'")
    }

    return $resultado
}

Write-Host "Levantando Auth API en 8001..."
Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy","Bypass","-File",$rutaAuthApi -WorkingDirectory $rutaProyecto | Out-Null
Start-Sleep -Seconds 2

Write-Host "Levantando Folder API en 8002..."
Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy","Bypass","-File",$rutaApiSegura -WorkingDirectory $rutaProyecto | Out-Null
Start-Sleep -Seconds 2

Write-Host "Levantando oauth2-proxy en 4180..."
Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy","Bypass","-File",$rutaOauth -WorkingDirectory $rutaProyecto | Out-Null
Start-Sleep -Seconds 3

Write-Host "Levantando Nginx..."
Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy","Bypass","-File",$rutaNginx -WorkingDirectory $rutaProyecto | Out-Null

$variables = Obtener-Variables-Env -RutaArchivo $rutaEnv
$puertoNginx = if ($variables.ContainsKey("NGINX_PORT")) { $variables["NGINX_PORT"] } else { "8087" }
$hostPublico = if ($variables.ContainsKey("NGINX_PUBLIC_HOST")) { $variables["NGINX_PUBLIC_HOST"] } else { "" }
$esquemaPublico = if ($variables.ContainsKey("NGINX_PUBLIC_SCHEME")) { $variables["NGINX_PUBLIC_SCHEME"] } else { "http" }
$sufijoPuerto = ""
if (($esquemaPublico -eq "https" -and $puertoNginx -ne "443") -or ($esquemaPublico -eq "http" -and $puertoNginx -ne "80")) {
    $sufijoPuerto = ":$puertoNginx"
}

Write-Host ""
Write-Host "Stack levantado."
if ($hostPublico) {
    Write-Host "Auth API: ${esquemaPublico}://$hostPublico$sufijoPuerto/auth/docs"
    Write-Host "Folder API: ${esquemaPublico}://$hostPublico$sufijoPuerto/folders/docs"
} else {
    Write-Host "Auth API: http://localhost:$puertoNginx/auth/docs"
    Write-Host "Folder API: http://localhost:$puertoNginx/folders/docs"
}
Write-Host "Acceso no autenticado redirige directamente a Entra ID."
