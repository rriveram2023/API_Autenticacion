param(
    [ValidateSet(16, 24, 32)]
    [int]$Longitud = 32
)

$alfabeto = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
$bytes = New-Object byte[] $Longitud
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)

$resultado = -join ($bytes | ForEach-Object {
    $alfabeto[$_ % $alfabeto.Length]
})

$resultado
