param(
    [string]$Hostname = "e3display.com",
    [string]$HostsPath = "C:\Windows\System32\drivers\etc\hosts",
    [switch]$MostrarIpSolamente
)

$ErrorActionPreference = "Stop"

function Obtener-IPv4Activa {
    $rutas = Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
        Where-Object { $_.NextHop -and $_.NextHop -ne "0.0.0.0" } |
        Sort-Object RouteMetric, InterfaceMetric

    foreach ($ruta in $rutas) {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $ruta.InterfaceIndex -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notlike "127.*" -and
                $_.IPAddress -notlike "169.254.*" -and
                $_.PrefixOrigin -ne "WellKnown"
            } |
            Sort-Object SkipAsSource, PrefixLength -Descending |
            Select-Object -First 1 -ExpandProperty IPAddress

        if ($ip) {
            return $ip
        }
    }

    throw "No se pudo determinar una IPv4 activa para este equipo."
}

function Requiere-Administrador {
    $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identidad)
    return -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$ipActual = Obtener-IPv4Activa

if ($MostrarIpSolamente) {
    Write-Host $ipActual
    exit 0
}

if (Requiere-Administrador) {
    throw "Ejecuta este script en PowerShell como administrador para modificar hosts."
}

$patron = "^\s*\d{1,3}(\.\d{1,3}){3}\s+$([regex]::Escape($Hostname))(\s|$)"
$lineas = @()
if (Test-Path $HostsPath) {
    $lineas = Get-Content -Path $HostsPath | Where-Object { $_ -notmatch $patron }
}

$lineas += "$ipActual $Hostname"
Set-Content -Path $HostsPath -Value $lineas -Encoding ascii

Write-Host "Hosts actualizado: $Hostname -> $ipActual"
