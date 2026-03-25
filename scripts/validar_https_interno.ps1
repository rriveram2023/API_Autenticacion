$ErrorActionPreference = "Stop"

$rutaProyecto = Split-Path -Parent $PSScriptRoot
$rutaEnv = Join-Path $rutaProyecto ".env"
$rutaNginxConf = Join-Path $rutaProyecto "nginx\conf\app.conf"

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

function Obtener-Valor {
    param(
        [hashtable]$Variables,
        [string]$Nombre,
        [string]$ValorPorDefecto = ""
    )

    if ($Variables.ContainsKey($Nombre) -and $Variables[$Nombre]) {
        return $Variables[$Nombre]
    }

    return $ValorPorDefecto
}

function Obtener-Sufijo-Puerto {
    param(
        [string]$Esquema,
        [int]$Puerto
    )

    if (($Esquema -eq "https" -and $Puerto -eq 443) -or ($Esquema -eq "http" -and $Puerto -eq 80)) {
        return ""
    }

    return ":$Puerto"
}

function Escribir-Resultado {
    param(
        [string]$Nombre,
        [bool]$Correcto,
        [string]$Detalle
    )

    $estado = if ($Correcto) { "OK" } else { "FAIL" }
    Write-Host ("[{0}] {1}: {2}" -f $estado, $Nombre, $Detalle)
}

function Obtener-NginxExe {
    param([string]$RutaProyecto)

    $rutas = @(
        (Join-Path $RutaProyecto "nginx-bin\nginx.exe")
        (Get-ChildItem -Path (Join-Path $RutaProyecto "nginx-bin") -Filter nginx.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        "C:\nginx\nginx.exe"
        "C:\Program Files\nginx\nginx.exe"
        "C:\Program Files (x86)\nginx\nginx.exe"
    ) | Where-Object { $_ }

    return $rutas | Where-Object { Test-Path $_ } | Select-Object -First 1
}

$variables = Obtener-Variables-Env -RutaArchivo $rutaEnv
$hostname = Obtener-Valor -Variables $variables -Nombre "TLS_HOSTNAME" -ValorPorDefecto (Obtener-Valor -Variables $variables -Nombre "NGINX_PUBLIC_HOST" -ValorPorDefecto "e3os.local")
$ipEsperada = Obtener-Valor -Variables $variables -Nombre "APP_SERVER_IP" -ValorPorDefecto ""
$subjectName = Obtener-Valor -Variables $variables -Nombre "TLS_CERT_SUBJECT_NAME" -ValorPorDefecto $hostname
$puertoHttps = [int](Obtener-Valor -Variables $variables -Nombre "TLS_HTTPS_PORT" -ValorPorDefecto (Obtener-Valor -Variables $variables -Nombre "NGINX_PORT" -ValorPorDefecto "443"))
$rutaCrt = Obtener-Valor -Variables $variables -Nombre "TLS_CERT_OUTPUT_PATH"
$rutaKey = Obtener-Valor -Variables $variables -Nombre "TLS_KEY_OUTPUT_PATH"
$esquema = Obtener-Valor -Variables $variables -Nombre "NGINX_PUBLIC_SCHEME" -ValorPorDefecto "https"
$sufijoPuerto = Obtener-Sufijo-Puerto -Esquema $esquema -Puerto $puertoHttps
$urlBase = "{0}://{1}{2}" -f $esquema, $hostname, $sufijoPuerto
$errores = 0

try {
    $ips = [System.Net.Dns]::GetHostAddresses($hostname) | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | ForEach-Object { $_.IPAddressToString }
    $coincide = (-not $ipEsperada) -or ($ips -contains $ipEsperada)
    if (-not $coincide) { $errores++ }
    Escribir-Resultado -Nombre "Resolucion local" -Correcto $coincide -Detalle "$hostname -> $($ips -join ', ')"
} catch {
    $errores++
    Escribir-Resultado -Nombre "Resolucion local" -Correcto $false -Detalle $_.Exception.Message
}

try {
    $certificado = Get-ChildItem -Path Cert:\LocalMachine\My |
        Where-Object { $_.HasPrivateKey -and $_.Subject -like "*CN=$subjectName*" } |
        Sort-Object NotBefore -Descending |
        Select-Object -First 1

    if (-not $certificado) {
        throw "No existe un certificado con CN=$subjectName en LocalMachine\\My"
    }

    $detalleCert = "Thumbprint=$($certificado.Thumbprint), vence=$($certificado.NotAfter.ToString('yyyy-MM-dd HH:mm'))"
    $valido = $certificado.NotAfter -gt (Get-Date)
    if (-not $valido) { $errores++ }
    Escribir-Resultado -Nombre "Certificado en store" -Correcto $valido -Detalle $detalleCert
} catch {
    $errores++
    Escribir-Resultado -Nombre "Certificado en store" -Correcto $false -Detalle $_.Exception.Message
}

try {
    $archivosExisten = (Test-Path $rutaCrt) -and (Test-Path $rutaKey)
    if (-not $archivosExisten) { $errores++ }
    Escribir-Resultado -Nombre "Archivos TLS" -Correcto $archivosExisten -Detalle "$rutaCrt | $rutaKey"
} catch {
    $errores++
    Escribir-Resultado -Nombre "Archivos TLS" -Correcto $false -Detalle $_.Exception.Message
}

try {
    $nginxExe = Obtener-NginxExe -RutaProyecto $rutaProyecto
    if (-not $nginxExe) {
        throw "No se encontro nginx.exe"
    }

    $prefijo = Join-Path $rutaProyecto "nginx\"
    $salidaTest = & $nginxExe -p $prefijo -c $rutaNginxConf -t 2>&1
    $configValida = $LASTEXITCODE -eq 0
    if (-not $configValida) { $errores++ }
    Escribir-Resultado -Nombre "nginx -t" -Correcto $configValida -Detalle (($salidaTest | Select-Object -Last 2) -join " ")
} catch {
    $errores++
    Escribir-Resultado -Nombre "nginx -t" -Correcto $false -Detalle $_.Exception.Message
}

try {
    $respuesta = & curl.exe -I --connect-timeout 5 $urlBase 2>&1
    $ok = $LASTEXITCODE -eq 0
    if (-not $ok) { $errores++ }
    Escribir-Resultado -Nombre "Endpoint HTTPS" -Correcto $ok -Detalle (($respuesta | Select-Object -First 3) -join " ")
} catch {
    $errores++
    Escribir-Resultado -Nombre "Endpoint HTTPS" -Correcto $false -Detalle $_.Exception.Message
}

if ($errores -gt 0) {
    throw "La validacion HTTPS detecto $errores problema(s)."
}
