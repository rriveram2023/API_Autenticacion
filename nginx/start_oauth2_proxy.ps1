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

function Obtener-Valor {
    param(
        [hashtable]$Variables,
        [string]$Nombre,
        [string]$ValorPorDefecto = ""
    )

    if ($Variables.ContainsKey($Nombre)) {
        return $Variables[$Nombre]
    }
    return $ValorPorDefecto
}

function Validar-CookieSecret {
    param([string]$Valor)

    if (-not $Valor) {
        return $false
    }

    if ($Valor.Length -in @(16, 24, 32)) {
        return $true
    }

    try {
        $bytes = [Convert]::FromBase64String($Valor)
        return $bytes.Length -in @(16, 24, 32)
    } catch {
        return $false
    }
}

function Probar-Resolucion-Host {
    param([string]$HostObjetivo)

    if (-not $HostObjetivo) {
        return $false
    }

    if ($HostObjetivo -in @("localhost", "127.0.0.1")) {
        return $true
    }

    try {
        [System.Net.Dns]::GetHostEntry($HostObjetivo) | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Construir-Url-HostPublico {
    param([hashtable]$Variables)

    $hostPublico = Obtener-Valor -Variables $Variables -Nombre "NGINX_PUBLIC_HOST"
    if (-not $hostPublico) {
        return ""
    }

    $puertoNginx = Obtener-Valor -Variables $Variables -Nombre "NGINX_PORT" -ValorPorDefecto "8087"
    $esquemaPublico = Obtener-Valor -Variables $Variables -Nombre "NGINX_PUBLIC_SCHEME" -ValorPorDefecto "http"
    return "${esquemaPublico}://${hostPublico}:${puertoNginx}"
}

function Resolver-RedirectUrl {
    param([hashtable]$Variables)

    $puertoNginx = Obtener-Valor -Variables $Variables -Nombre "NGINX_PORT" -ValorPorDefecto "8087"
    $redirectLocalPorDefecto = "http://localhost:$puertoNginx/auth/callback"
    $urlBasePublica = Construir-Url-HostPublico -Variables $Variables

    $redirectUrlExplicita = Obtener-Valor -Variables $Variables -Nombre "OAUTH2_PROXY_REDIRECT_URL"
    if ($redirectUrlExplicita) {
        return $redirectUrlExplicita
    }

    if ($urlBasePublica) {
        return "$urlBasePublica/auth/callback"
    }

    $redirectUrls = Obtener-Valor -Variables $Variables -Nombre "OAUTH2_PROXY_REDIRECT_URLS"
    if (-not $redirectUrls) {
        return $redirectLocalPorDefecto
    }

    $candidatas = $redirectUrls.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($candidata in $candidatas) {
        try {
            $uri = [Uri]$candidata
            if (Probar-Resolucion-Host -HostObjetivo $uri.Host) {
                return $candidata
            }
        } catch {
        }
    }

    return $candidatas[-1]
}

function Resolver-WhitelistDomains {
    param(
        [hashtable]$Variables,
        [string]$RedirectUrl
    )

    $puertoNginx = Obtener-Valor -Variables $Variables -Nombre "NGINX_PORT" -ValorPorDefecto "8087"
    $dominios = New-Object System.Collections.Generic.List[string]

    foreach ($base in @("localhost:$puertoNginx", "127.0.0.1:$puertoNginx")) {
        if (-not $dominios.Contains($base)) {
            $dominios.Add($base)
        }
    }

    $configurados = Obtener-Valor -Variables $Variables -Nombre "OAUTH2_PROXY_WHITELIST_DOMAINS"
    foreach ($dominio in ($configurados.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        if (-not $dominios.Contains($dominio)) {
            $dominios.Add($dominio)
        }
    }

    if ($RedirectUrl) {
        try {
            $redirectUri = [Uri]$RedirectUrl
            $dominioRedirect = if ($redirectUri.IsDefaultPort) { $redirectUri.Host } else { "$($redirectUri.Host):$($redirectUri.Port)" }
            if (-not $dominios.Contains($dominioRedirect)) {
                $dominios.Add($dominioRedirect)
            }
        } catch {
        }
    }

    return $dominios
}

$variables = Obtener-Variables-Env -RutaArchivo $rutaEnv
$rutaBinario = if ($variables.ContainsKey("OAUTH2_PROXY_EXE_PATH")) { $variables["OAUTH2_PROXY_EXE_PATH"] } else { "" }

if (-not $rutaBinario) {
    $rutaBinario = Get-ChildItem -Path (Join-Path $rutaProyecto "oauth2-proxy-bin") -Recurse -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer -and $_.Name -eq "oauth2-proxy.exe" } |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $rutaBinario) {
    $rutaBinario = Get-ChildItem -Path (Join-Path $rutaProyecto "oauth2-proxy-bin") -Recurse -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer -and $_.Name -eq "oauth2-proxy" } |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $rutaBinario -or -not (Test-Path $rutaBinario)) {
    throw "No se encontro el ejecutable de oauth2-proxy. Configura OAUTH2_PROXY_EXE_PATH o coloca el binario en oauth2-proxy-bin."
}

$tenantId = Obtener-Valor -Variables $variables -Nombre "ENTRA_TENANT_ID"
$clientId = Obtener-Valor -Variables $variables -Nombre "OAUTH2_PROXY_CLIENT_ID"
$clientSecret = Obtener-Valor -Variables $variables -Nombre "OAUTH2_PROXY_CLIENT_SECRET"
$cookieSecret = Obtener-Valor -Variables $variables -Nombre "OAUTH2_PROXY_COOKIE_SECRET"
$redirectUrl = Resolver-RedirectUrl -Variables $variables
$httpAddress = Obtener-Valor -Variables $variables -Nombre "OAUTH2_PROXY_HTTP_ADDRESS" -ValorPorDefecto "127.0.0.1:4180"
$emailDomain = Obtener-Valor -Variables $variables -Nombre "OAUTH2_PROXY_EMAIL_DOMAIN" -ValorPorDefecto "*"
$cookieSecure = Obtener-Valor -Variables $variables -Nombre "OAUTH2_PROXY_COOKIE_SECURE" -ValorPorDefecto "false"
$sessionCookieMinimal = Obtener-Valor -Variables $variables -Nombre "OAUTH2_PROXY_SESSION_COOKIE_MINIMAL" -ValorPorDefecto "true"
$allowedGroups = Obtener-Valor -Variables $variables -Nombre "OAUTH2_PROXY_ALLOWED_GROUPS"
$whitelistDomains = Resolver-WhitelistDomains -Variables $variables -RedirectUrl $redirectUrl

$faltantes = @()
if (-not $tenantId) { $faltantes += "ENTRA_TENANT_ID" }
if (-not $clientId) { $faltantes += "OAUTH2_PROXY_CLIENT_ID" }
if (-not $clientSecret) { $faltantes += "OAUTH2_PROXY_CLIENT_SECRET" }
if (-not $cookieSecret) { $faltantes += "OAUTH2_PROXY_COOKIE_SECRET" }

if ($faltantes.Count -gt 0) {
    throw "Faltan variables para Entra ID en .env: $($faltantes -join ', ')"
}

if (-not (Validar-CookieSecret -Valor $cookieSecret)) {
    throw "OAUTH2_PROXY_COOKIE_SECRET debe tener 16, 24 o 32 bytes efectivos. Usa un valor ASCII de 16/24/32 caracteres o genera uno compatible con .\\scripts\\generar_cookie_secret.ps1."
}

$argumentos = @(
    "--provider=entra-id",
    "--reverse-proxy=true",
    "--set-xauthrequest=true",
    "--pass-user-headers=true",
    "--upstream=static://202",
    "--http-address=$httpAddress",
    "--redirect-url=$redirectUrl",
    "--client-id=$clientId",
    "--client-secret=$clientSecret",
    "--cookie-secret=$cookieSecret",
    "--cookie-secure=$cookieSecure",
    "--cookie-samesite=lax",
    "--session-cookie-minimal=$sessionCookieMinimal",
    "--scope=openid profile email",
    "--email-domain=$emailDomain",
    "--oidc-issuer-url=https://login.microsoftonline.com/$tenantId/v2.0",
    "--entra-id-allowed-tenant=$tenantId",
    "--skip-provider-button=true"
)

foreach ($dominio in $whitelistDomains) {
    $argumentos += "--whitelist-domain=$dominio"
}

if ($allowedGroups) {
    foreach ($grupo in ($allowedGroups.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $argumentos += "--allowed-group=$grupo"
    }
}

Write-Host "Levantando oauth2-proxy con Entra ID sobre $httpAddress"
Write-Host "Redirect URL seleccionada: $redirectUrl"
& $rutaBinario @argumentos
