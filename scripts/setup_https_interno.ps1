param(
    [string]$HostnamePublico = "e3os.local",
    [string]$IpServidor = "10.1.6.192",
    [string]$CaHost = "enigma.e3.lan",
    [string]$CaName = "E3 Certificate Server",
    [string]$TemplateCertificado = "WebServer",
    [switch]$AutodescubrirCA,
    [switch]$ActualizarHostsLocal,
    [switch]$OmitirValidacionFinal
)

$ErrorActionPreference = "Stop"

$rutaProyecto = Split-Path -Parent $PSScriptRoot
$rutaEnv = Join-Path $rutaProyecto ".env"
$rutaNginxConf = Join-Path $rutaProyecto "nginx\conf\app.conf"
$rutaCerts = Join-Path $rutaProyecto "nginx\certs"
$rutaTrabajo = Join-Path $rutaProyecto "salidas\https_setup"
$marcaTiempo = Get-Date -Format "yyyyMMdd_HHmmss"
$rutaLog = Join-Path $rutaTrabajo "setup_https_interno_$marcaTiempo.log"

function Es-Administrador {
    $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identidad)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Asegurar-Directorio {
    param([string]$Ruta)

    New-Item -ItemType Directory -Force -Path $Ruta | Out-Null
}

function Escribir-Log {
    param(
        [string]$Mensaje,
        [string]$Nivel = "INFO"
    )

    $linea = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Nivel, $Mensaje
    Write-Host $linea
    Add-Content -Path $rutaLog -Value $linea
}

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

function Respaldar-Archivo {
    param([string]$Ruta)

    if (-not (Test-Path $Ruta)) {
        return ""
    }

    $respaldo = "$Ruta.bak.$marcaTiempo"
    Copy-Item -Path $Ruta -Destination $respaldo -Force
    return $respaldo
}

function Actualizar-Env {
    param(
        [string]$Ruta,
        [hashtable]$Valores
    )

    $lineas = New-Object System.Collections.Generic.List[string]
    if (Test-Path $Ruta) {
        foreach ($linea in Get-Content -Path $Ruta) {
            $lineas.Add($linea)
        }
    }

    foreach ($clave in $Valores.Keys) {
        $patron = '^\s*' + [regex]::Escape($clave) + '='
        $reemplazada = $false

        for ($i = 0; $i -lt $lineas.Count; $i++) {
            if ($lineas[$i] -match $patron) {
                $lineas[$i] = "$clave=$($Valores[$clave])"
                $reemplazada = $true
                break
            }
        }

        if (-not $reemplazada) {
            $lineas.Add("$clave=$($Valores[$clave])")
        }
    }

    Set-Content -Path $Ruta -Value $lineas -Encoding ascii
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

function Convertir-A-BytesLongitudAsn1 {
    param([int]$Longitud)

    if ($Longitud -lt 128) {
        return [byte[]]@($Longitud)
    }

    $bytes = New-Object System.Collections.Generic.List[byte]
    $valor = $Longitud
    while ($valor -gt 0) {
        $bytes.Insert(0, [byte]($valor -band 0xFF))
        $valor = [math]::Floor($valor / 256)
    }

    $prefijo = [byte](0x80 -bor $bytes.Count)
    $resultado = New-Object System.Collections.Generic.List[byte]
    $resultado.Add($prefijo)
    $resultado.AddRange($bytes)
    return $resultado.ToArray()
}

function Unir-Bytes {
    param([byte[][]]$Bloques)

    $resultado = New-Object System.Collections.Generic.List[byte]
    foreach ($bloque in $Bloques) {
        if ($bloque) {
            $resultado.AddRange($bloque)
        }
    }

    return $resultado.ToArray()
}

function Convertir-A-EnteroAsn1 {
    param([byte[]]$Valor)

    if (-not $Valor -or $Valor.Length -eq 0) {
        $Valor = [byte[]]@(0)
    }

    $indice = 0
    while ($indice -lt ($Valor.Length - 1) -and $Valor[$indice] -eq 0) {
        $indice++
    }

    $normalizado = $Valor[$indice..($Valor.Length - 1)]
    if ($normalizado[0] -ge 0x80) {
        $normalizado = Unir-Bytes @([byte[]]@(0), $normalizado)
    }

    return Unir-Bytes @(
        [byte[]]@(0x02),
        (Convertir-A-BytesLongitudAsn1 -Longitud $normalizado.Length),
        $normalizado
    )
}

function Convertir-RsaPkcs1 {
    param([System.Security.Cryptography.RSAParameters]$Parametros)

    $partes = @(
        (Convertir-A-EnteroAsn1 -Valor ([byte[]]@(0))),
        (Convertir-A-EnteroAsn1 -Valor $Parametros.Modulus),
        (Convertir-A-EnteroAsn1 -Valor $Parametros.Exponent),
        (Convertir-A-EnteroAsn1 -Valor $Parametros.D),
        (Convertir-A-EnteroAsn1 -Valor $Parametros.P),
        (Convertir-A-EnteroAsn1 -Valor $Parametros.Q),
        (Convertir-A-EnteroAsn1 -Valor $Parametros.DP),
        (Convertir-A-EnteroAsn1 -Valor $Parametros.DQ),
        (Convertir-A-EnteroAsn1 -Valor $Parametros.InverseQ)
    )

    $contenido = Unir-Bytes -Bloques $partes
    return Unir-Bytes @(
        [byte[]]@(0x30),
        (Convertir-A-BytesLongitudAsn1 -Longitud $contenido.Length),
        $contenido
    )
}

function Convertir-A-Pem {
    param(
        [string]$Etiqueta,
        [byte[]]$Bytes
    )

    $base64 = [Convert]::ToBase64String($Bytes)
    $partes = for ($i = 0; $i -lt $base64.Length; $i += 64) {
        $longitud = [Math]::Min(64, $base64.Length - $i)
        $base64.Substring($i, $longitud)
    }

    return "-----BEGIN $Etiqueta-----`r`n{0}`r`n-----END $Etiqueta-----`r`n" -f ($partes -join "`r`n")
}

function Escribir-Pem-DesdePfx {
    param(
        [string]$RutaPfx,
        [string]$ContrasenaPfx,
        [string]$RutaCrt,
        [string]$RutaKey
    )

    $banderas = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
    $banderas = $banderas -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
    $certificado = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    $certificado.Import($RutaPfx, $ContrasenaPfx, $banderas)

    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($certificado)
    if (-not $rsa) {
        throw "No se pudo obtener la llave privada RSA del certificado exportado."
    }

    $parametros = $rsa.ExportParameters($true)
    $bytesCert = $certificado.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    $bytesKey = Convertir-RsaPkcs1 -Parametros $parametros

    Set-Content -Path $RutaCrt -Value (Convertir-A-Pem -Etiqueta "CERTIFICATE" -Bytes $bytesCert) -Encoding ascii
    Set-Content -Path $RutaKey -Value (Convertir-A-Pem -Etiqueta "RSA PRIVATE KEY" -Bytes $bytesKey) -Encoding ascii
}

function Actualizar-HostsLocal {
    param(
        [string]$Hostname,
        [string]$Ip
    )

    $rutaHosts = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
    $lineas = if (Test-Path $rutaHosts) { Get-Content -Path $rutaHosts } else { @() }
    $patron = '^\s*(\d{1,3}\.){3}\d{1,3}\s+' + [regex]::Escape($Hostname) + '(\s|$)'
    $nuevas = New-Object System.Collections.Generic.List[string]
    $encontrado = $false

    foreach ($linea in $lineas) {
        if ($linea -match $patron) {
            if (-not $encontrado) {
                $nuevas.Add("$Ip`t$Hostname")
                $encontrado = $true
            }
            continue
        }
        $nuevas.Add($linea)
    }

    if (-not $encontrado) {
        $nuevas.Add("$Ip`t$Hostname")
    }

    Set-Content -Path $rutaHosts -Value $nuevas -Encoding ascii
}

function Construir-ConfigNginx {
    param(
        [string]$Hostname,
        [int]$PuertoHttps,
        [int]$PuertoRedirectHttp,
        [int]$PuertoLegado,
        [string]$RutaCrt,
        [string]$RutaKey
    )

    $bloquesRedirect = New-Object System.Collections.Generic.List[string]
    foreach ($puerto in @($PuertoRedirectHttp, $PuertoLegado) | Where-Object { $_ -gt 0 } | Select-Object -Unique) {
        if ($puerto -eq $PuertoHttps) {
            continue
        }

        $bloquesRedirect.Add(@"
    server {
        listen $puerto;
        server_name $Hostname;
        return 301 https://$Hostname`$request_uri;
    }
"@)
    }

    return @"
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout  65;
    large_client_header_buffers 4 16k;
    proxy_buffer_size 16k;
    proxy_buffers 8 16k;
    proxy_busy_buffers_size 32k;

    upstream folder_api_backend_secure {
        server 127.0.0.1:8002;
    }

    upstream oauth2_proxy_backend {
        server 127.0.0.1:4180;
    }

$($bloquesRedirect -join "`r`n")

    server {
        listen $PuertoHttps ssl;
        server_name $Hostname;

        ssl_certificate     $RutaCrt;
        ssl_certificate_key $RutaKey;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_session_cache   shared:SSL:10m;
        ssl_session_timeout 10m;

        location /oauth2/ {
            proxy_pass http://oauth2_proxy_backend;
            proxy_set_header Host `$http_host;
            proxy_set_header X-Real-IP `$remote_addr;
            proxy_set_header X-Forwarded-Proto `$scheme;
            proxy_set_header X-Forwarded-Host `$http_host;
            proxy_set_header X-Forwarded-Port `$server_port;
            proxy_set_header X-Auth-Request-Redirect `$scheme://`$http_host`$request_uri;
            proxy_set_header X-Authenticated-User "";
        }

        location = /oauth2/auth {
            proxy_pass http://oauth2_proxy_backend;
            proxy_set_header Host `$http_host;
            proxy_set_header X-Real-IP `$remote_addr;
            proxy_set_header X-Forwarded-Host `$http_host;
            proxy_set_header X-Forwarded-Proto `$scheme;
            proxy_set_header X-Forwarded-Port `$server_port;
            proxy_set_header X-Forwarded-Uri `$request_uri;
            proxy_set_header X-Authenticated-User "";
            proxy_set_header Content-Length "";
            proxy_pass_request_body off;
        }

        location @entra_login {
            return 302 /oauth2/start?rd=`$scheme://`$http_host`$request_uri;
        }

        location / {
            auth_request /oauth2/auth;
            error_page 401 = @entra_login;

            auth_request_set `$usuario `$upstream_http_x_auth_request_user;
            auth_request_set `$correo `$upstream_http_x_auth_request_email;

            proxy_pass http://folder_api_backend_secure;
            proxy_http_version 1.1;
            proxy_set_header Host `$http_host;
            proxy_set_header X-Real-IP `$remote_addr;
            proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto `$scheme;
            proxy_set_header X-Forwarded-Host `$http_host;
            proxy_set_header X-Forwarded-Port `$server_port;
            proxy_set_header X-Authenticated-User `$usuario;
            proxy_set_header X-Authenticated-Email `$correo;
        }
    }
}
"@
}

function Obtener-Certificado-Instalado {
    param(
        [string]$SubjectName,
        [datetime]$NoAntesDe
    )

    $certificados = Get-ChildItem -Path Cert:\LocalMachine\My |
        Where-Object {
            $_.HasPrivateKey -and
            $_.Subject -like "*CN=$SubjectName*" -and
            $_.NotBefore -ge $NoAntesDe.AddMinutes(-5)
        } |
        Sort-Object NotBefore -Descending

    return $certificados | Select-Object -First 1
}

function Probar-CA {
    param(
        [string]$ConfigCa,
        [bool]$UsarAutodescubrimiento
    )

    if ($UsarAutodescubrimiento -or $ConfigCa -eq "-") {
        Escribir-Log -Mensaje "Se usara descubrimiento automatico de CA empresarial desde este equipo."
        return
    }

    $partesCa = $ConfigCa.Split("\", 2)
    $hostCa = $partesCa[0]
    try {
        [System.Net.Dns]::GetHostEntry($hostCa) | Out-Null
    } catch {
        throw "No se puede resolver el host de la CA '$hostCa'. Verifica DNS corporativo, conectividad de red o agrega una entrada temporal en hosts."
    }

    $salida = & certutil.exe -config $ConfigCa -ping 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo alcanzar la CA '$ConfigCa'. Salida: $($salida -join ' ')"
    }
}

function Probar-Template {
    param(
        [string]$ConfigCa,
        [string]$Template,
        [bool]$UsarAutodescubrimiento
    )

    if ($UsarAutodescubrimiento -or $ConfigCa -eq "-") {
        Escribir-Log -Mensaje "La validacion de plantilla se delegara al flujo de inscripcion empresarial para '$Template'."
        return
    }

    $salida = & certutil.exe -config $ConfigCa -CATemplates 2>&1
    if ($LASTEXITCODE -ne 0) {
        Escribir-Log -Nivel "WARN" -Mensaje "No se pudieron listar las plantillas de la CA. Se intentara la solicitud directa con '$Template'."
        return
    }

    if (-not ($salida -match [regex]::Escape($Template))) {
        Escribir-Log -Nivel "WARN" -Mensaje "La plantilla '$Template' no aparece en la lista de la CA. Si la solicitud falla, ajusta TLS_CERT_TEMPLATE."
    }
}

function Solicitar-Certificado {
    param(
        [string]$Hostname,
        [string]$ConfigCa,
        [string]$Template,
        [bool]$UsarAutodescubrimiento
    )

    if ($UsarAutodescubrimiento -or $ConfigCa -eq "-") {
        Escribir-Log -Mensaje "Solicitando certificado mediante inscripcion empresarial automatica para $Hostname"
        try {
            Get-Certificate `
                -Template $Template `
                -SubjectName "CN=$Hostname" `
                -DnsName $Hostname `
                -CertStoreLocation "Cert:\LocalMachine\My" | Out-Null
            return $null
        } catch {
            throw "Fallo la inscripcion automatica con Get-Certificate. Verifica permisos del equipo/usuario y la plantilla '$Template'. Detalle: $($_.Exception.Message)"
        }
    }

    $rutaInf = Join-Path $rutaTrabajo "$Hostname.inf"
    $rutaReq = Join-Path $rutaTrabajo "$Hostname.req"
    $rutaCer = Join-Path $rutaTrabajo "$Hostname.cer"

    $contenidoInf = @"
[Version]
Signature=`"$Windows NT$`"

[NewRequest]
Subject = `"CN=$Hostname`"
Exportable = TRUE
KeyLength = 2048
KeyAlgorithm = RSA
MachineKeySet = TRUE
SMIME = FALSE
PrivateKeyArchive = FALSE
UserProtected = FALSE
UseExistingKeySet = FALSE
ProviderName = `"Microsoft RSA SChannel Cryptographic Provider`"
ProviderType = 12
RequestType = PKCS10
HashAlgorithm = sha256
KeyUsage = 0xa0

[Extensions]
2.5.29.17 = `"{text}`"
_continue_ = `"dns=$Hostname`"

[RequestAttributes]
CertificateTemplate = $Template
"@

    Set-Content -Path $rutaInf -Value $contenidoInf -Encoding ascii

    Escribir-Log -Mensaje "Generando CSR para $Hostname"
    $salidaNew = & certreq.exe -f -q -machine -new $rutaInf $rutaReq 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo al generar la CSR. Salida: $($salidaNew -join ' ')"
    }

    Escribir-Log -Mensaje "Solicitando certificado a la CA $ConfigCa usando plantilla $Template"
    $salidaSubmit = & certreq.exe -f -q -machine -submit -config $ConfigCa -attrib "CertificateTemplate:$Template" $rutaReq $rutaCer 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo al solicitar el certificado. Verifica permisos y plantilla '$Template'. Salida: $($salidaSubmit -join ' ')"
    }

    Escribir-Log -Mensaje "Aceptando certificado emitido en LocalMachine\\My"
    $salidaAccept = & certreq.exe -f -q -machine -accept $rutaCer 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo al aceptar el certificado emitido. Salida: $($salidaAccept -join ' ')"
    }

    return $rutaCer
}

function Exportar-Certificado {
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificado,
        [string]$RutaPfx,
        [string]$RutaCrt,
        [string]$RutaKey,
        [string]$RutaPassword,
        [string]$ContrasenaPfx
    )

    if (-not $ContrasenaPfx) {
        $ContrasenaPfx = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
        Escribir-Log -Nivel "WARN" -Mensaje "No se definio TLS_PFX_PASSWORD. Se genero una contrasena aleatoria y se guardara en $RutaPassword"
    }

    $segura = ConvertTo-SecureString -String $ContrasenaPfx -AsPlainText -Force
    Export-PfxCertificate -Cert $Certificado.PSPath -FilePath $RutaPfx -Password $segura -Force | Out-Null
    Set-Content -Path $RutaPassword -Value $ContrasenaPfx -Encoding ascii
    Escribir-Pem-DesdePfx -RutaPfx $RutaPfx -ContrasenaPfx $ContrasenaPfx -RutaCrt $RutaCrt -RutaKey $RutaKey
}

Asegurar-Directorio -Ruta $rutaTrabajo
Asegurar-Directorio -Ruta $rutaCerts
New-Item -ItemType File -Force -Path $rutaLog | Out-Null

if (-not (Es-Administrador)) {
    throw "Este script requiere una sesion de PowerShell abierta como administrador para instalar el certificado en LocalMachine\\My y opcionalmente editar hosts."
}

$variables = Obtener-Variables-Env -RutaArchivo $rutaEnv
$autodescubrimientoCa = $AutodescubrirCA.IsPresent
if (-not $autodescubrimientoCa) {
    $valorEnvAutodesc = Obtener-Valor -Variables $variables -Nombre "TLS_CA_AUTO_DISCOVER"
    if ($valorEnvAutodesc) {
        $autodescubrimientoCa = $valorEnvAutodesc.ToLowerInvariant() -in @("1", "true", "yes", "si")
    }
}

$configCa = "{0}\{1}" -f (Obtener-Valor -Variables $variables -Nombre "TLS_CA_HOST" -ValorPorDefecto $CaHost), (Obtener-Valor -Variables $variables -Nombre "TLS_CA_NAME" -ValorPorDefecto $CaName)
$hostnameObjetivo = Obtener-Valor -Variables $variables -Nombre "TLS_HOSTNAME" -ValorPorDefecto $HostnamePublico
$ipObjetivo = Obtener-Valor -Variables $variables -Nombre "APP_SERVER_IP" -ValorPorDefecto $IpServidor
$templateObjetivo = Obtener-Valor -Variables $variables -Nombre "TLS_CERT_TEMPLATE" -ValorPorDefecto $TemplateCertificado
$puertoHttps = [int](Obtener-Valor -Variables $variables -Nombre "TLS_HTTPS_PORT" -ValorPorDefecto "443")
$puertoRedirect = [int](Obtener-Valor -Variables $variables -Nombre "TLS_HTTP_REDIRECT_PORT" -ValorPorDefecto "80")
$puertoLegado = [int](Obtener-Valor -Variables $variables -Nombre "NGINX_PORT" -ValorPorDefecto "8087")
$rutaPfx = Obtener-Valor -Variables $variables -Nombre "TLS_PFX_OUTPUT_PATH" -ValorPorDefecto (Join-Path $rutaCerts "$hostnameObjetivo.pfx")
$rutaCrt = Obtener-Valor -Variables $variables -Nombre "TLS_CERT_OUTPUT_PATH" -ValorPorDefecto (Join-Path $rutaCerts "$hostnameObjetivo.crt")
$rutaKey = Obtener-Valor -Variables $variables -Nombre "TLS_KEY_OUTPUT_PATH" -ValorPorDefecto (Join-Path $rutaCerts "$hostnameObjetivo.key")
$rutaPassword = Obtener-Valor -Variables $variables -Nombre "TLS_PFX_PASSWORD_FILE" -ValorPorDefecto (Join-Path $rutaCerts "$hostnameObjetivo.pfx.password.txt")
$contrasenaPfx = Obtener-Valor -Variables $variables -Nombre "TLS_PFX_PASSWORD"
$subjectName = Obtener-Valor -Variables $variables -Nombre "TLS_CERT_SUBJECT_NAME" -ValorPorDefecto $hostnameObjetivo
$esquemaPublico = "https"
$sufijoPuerto = Obtener-Sufijo-Puerto -Esquema $esquemaPublico -Puerto $puertoHttps
$redirectUrl = "{0}://{1}{2}/oauth2/callback" -f $esquemaPublico, $hostnameObjetivo, $sufijoPuerto

Escribir-Log -Mensaje "Preparando HTTPS interno para $hostnameObjetivo con redirect URI $redirectUrl"
if ($autodescubrimientoCa -or $configCa -eq "-") {
    $configCa = "-"
    Escribir-Log -Mensaje "Usando descubrimiento automatico de CA empresarial y plantilla $templateObjetivo"
} else {
    Escribir-Log -Mensaje "Usando CA $configCa y plantilla $templateObjetivo"
}

Probar-CA -ConfigCa $configCa -UsarAutodescubrimiento $autodescubrimientoCa
Probar-Template -ConfigCa $configCa -Template $templateObjetivo -UsarAutodescubrimiento $autodescubrimientoCa

if ($ActualizarHostsLocal) {
    Escribir-Log -Mensaje "Actualizando hosts local con $ipObjetivo -> $hostnameObjetivo"
    Actualizar-HostsLocal -Hostname $hostnameObjetivo -Ip $ipObjetivo
}

$inicioSolicitud = Get-Date
Solicitar-Certificado -Hostname $hostnameObjetivo -ConfigCa $configCa -Template $templateObjetivo -UsarAutodescubrimiento $autodescubrimientoCa | Out-Null
$certificado = Obtener-Certificado-Instalado -SubjectName $subjectName -NoAntesDe $inicioSolicitud

if (-not $certificado) {
    throw "No se encontro el certificado emitido para $subjectName en Cert:\LocalMachine\My despues de la solicitud."
}

Escribir-Log -Mensaje "Certificado emitido con thumbprint $($certificado.Thumbprint)"
Exportar-Certificado -Certificado $certificado -RutaPfx $rutaPfx -RutaCrt $rutaCrt -RutaKey $rutaKey -RutaPassword $rutaPassword -ContrasenaPfx $contrasenaPfx
Escribir-Log -Mensaje "Artefactos exportados a $rutaPfx, $rutaCrt y $rutaKey"

$respaldoEnv = Respaldar-Archivo -Ruta $rutaEnv
if ($respaldoEnv) {
    Escribir-Log -Mensaje "Respaldo de .env creado en $respaldoEnv"
}

$respaldoNginx = Respaldar-Archivo -Ruta $rutaNginxConf
if ($respaldoNginx) {
    Escribir-Log -Mensaje "Respaldo de nginx conf creado en $respaldoNginx"
}

Actualizar-Env -Ruta $rutaEnv -Valores @{
    "APP_SERVER_IP" = $ipObjetivo
    "NGINX_PUBLIC_HOST" = $hostnameObjetivo
    "NGINX_PUBLIC_SCHEME" = $esquemaPublico
    "NGINX_PORT" = "$puertoHttps"
    "NGINX_LEGACY_HTTP_PORT" = "$puertoLegado"
    "TLS_HOSTNAME" = $hostnameObjetivo
    "TLS_CA_HOST" = $(if ($configCa.Contains("\")) { $configCa.Split("\", 2)[0] } else { "" })
    "TLS_CA_NAME" = $(if ($configCa.Contains("\")) { $configCa.Split("\", 2)[1] } else { "" })
    "TLS_CA_AUTO_DISCOVER" = $(if ($autodescubrimientoCa -or $configCa -eq "-") { "true" } else { "false" })
    "TLS_CERT_TEMPLATE" = $templateObjetivo
    "TLS_CERT_SUBJECT_NAME" = $subjectName
    "TLS_HTTPS_PORT" = "$puertoHttps"
    "TLS_HTTP_REDIRECT_PORT" = "$puertoRedirect"
    "TLS_PFX_OUTPUT_PATH" = $rutaPfx
    "TLS_CERT_OUTPUT_PATH" = $rutaCrt
    "TLS_KEY_OUTPUT_PATH" = $rutaKey
    "TLS_PFX_PASSWORD_FILE" = $rutaPassword
    "OAUTH2_PROXY_REDIRECT_URL" = $redirectUrl
    "OAUTH2_PROXY_REDIRECT_URLS" = $redirectUrl
    "OAUTH2_PROXY_WHITELIST_DOMAINS" = $hostnameObjetivo
    "OAUTH2_PROXY_COOKIE_SECURE" = "true"
}

$contenidoNginx = Construir-ConfigNginx -Hostname $hostnameObjetivo -PuertoHttps $puertoHttps -PuertoRedirectHttp $puertoRedirect -PuertoLegado $puertoLegado -RutaCrt $rutaCrt -RutaKey $rutaKey
Set-Content -Path $rutaNginxConf -Value $contenidoNginx -Encoding ascii
Escribir-Log -Mensaje "Configuracion HTTPS de nginx generada en $rutaNginxConf"

if (-not $OmitirValidacionFinal) {
    $rutaValidacion = Join-Path $PSScriptRoot "validar_https_interno.ps1"
    Escribir-Log -Mensaje "Ejecutando validacion final"
    & $rutaValidacion
}

Escribir-Log -Mensaje "Proceso completado. Ya puedes registrar en Entra ID la URI $redirectUrl si aun no existe."
