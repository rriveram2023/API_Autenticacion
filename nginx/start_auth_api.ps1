$ErrorActionPreference = "Stop"

$rutaProyecto = Split-Path -Parent $PSScriptRoot
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

$variables = Obtener-Variables-Env -RutaArchivo $rutaEnv
$rutaPython = if ($variables.ContainsKey("PYTHON_EXE_PATH")) { $variables["PYTHON_EXE_PATH"] } else { Join-Path $rutaProyecto ".venv\Scripts\python.exe" }

if (-not (Test-Path $rutaPython)) {
    throw "No existe el entorno virtual en $rutaPython"
}

$apiHost = if ($variables.ContainsKey("AUTH_API_HOST")) { $variables["AUTH_API_HOST"] } else { "127.0.0.1" }
$apiPort = if ($variables.ContainsKey("AUTH_API_PORT")) { $variables["AUTH_API_PORT"] } else { "8001" }

Write-Host "Levantando Auth API en $apiHost`:$apiPort"
& $rutaPython -m uvicorn services.auth_api.app:app --host $apiHost --port $apiPort
