#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidatePattern('^RUN-[A-Z0-9][A-Z0-9_-]{5,80}$')]
    [string]$RunId,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\artifacts\rescue-pilot'),

    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ManifestPath,

    [switch]$RequestPass
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$requiredScenarios = @(
    'ROSTER',
    'TRIAGE',
    'CASES',
    'CLUSTERS',
    'ZONES',
    'AUTHORITY',
    'GEOJSON',
    'P0-SOS-NO-AUDIENCE',
    'P0-SOS-ACK',
    'P0-STORE-REBOOT',
    'P0-RESCUE-KILL-DOZE',
    'P0-PRIVATE-NOISE',
    'P0-FOUR-NODE-TWO-HOP',
    'P0-LAN-PI',
    'P0-RADAR-10M',
    'P0-BATTERY-24H',
    'P0-IOS-MESH-RESTART',
    'P0-INTEROP-OFF',
    'P0-PANIC-WIPE',
    'P0-OPTICAL-TRUST'
)
$requiredEvidenceCategories = @(
    'android-log',
    'diagnostics-export',
    'operator-report',
    'ui-evidence',
    'topology-control',
    'hardware-inventory',
    'ios-evidence',
    'anchor-evidence',
    'meshtastic-evidence',
    'lora-evidence'
)

function Test-Tool {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ConnectedAndroidCount {
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -eq $adb) {
        return 0
    }
    $lines = & $adb.Source devices 2>$null
    return @($lines | Where-Object { $_ -match "`tdevice$" }).Count
}

if ($RequestPass) {
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        throw '-RequestPass requiere -ManifestPath.'
    }
    $resolvedManifest = (Resolve-Path -LiteralPath $ManifestPath).Path
    $runDirectory = Split-Path -Parent $resolvedManifest
    $manifest = Get-Content -LiteralPath $resolvedManifest -Raw | ConvertFrom-Json

    if ([int]$manifest.schema_version -ne 1) {
        throw 'Versión de manifiesto no soportada.'
    }
    if ([string]$manifest.status -eq 'PASS') {
        throw 'El manifiesto ya está marcado PASS; no se sobrescribirá.'
    }
    foreach ($hardwareName in @(
        'android_devices',
        'iphone_and_mac',
        'bitle_anchors',
        'raspberry_pi_bluez',
        'meshtastic_pair',
        'authorized_lora_pair'
    )) {
        if ([string]$manifest.hardware.$hardwareName -ne 'CONFIRMED') {
            throw "PASS bloqueado: hardware '$hardwareName' no está CONFIRMED."
        }
    }
    $confirmed = @($manifest.criteria_confirmed)
    foreach ($scenario in $requiredScenarios) {
        if ($scenario -notin $confirmed) {
            throw "PASS bloqueado: falta confirmar el escenario '$scenario'."
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.operator_attestation) -or
        [string]$manifest.operator_attestation -eq 'PENDING') {
        throw 'PASS bloqueado: falta operator_attestation.'
    }

    $evidence = @($manifest.evidence)
    foreach ($category in $requiredEvidenceCategories) {
        if ($category -notin @($evidence | ForEach-Object { [string]$_.category })) {
            throw "PASS bloqueado: falta evidencia de categoría '$category'."
        }
    }
    $basePath = [System.IO.Path]::GetFullPath($runDirectory) +
        [System.IO.Path]::DirectorySeparatorChar
    foreach ($item in $evidence) {
        $relative = [string]$item.path
        $expectedHash = ([string]$item.sha256).ToLowerInvariant()
        if ([System.IO.Path]::IsPathRooted($relative) -or $relative.Contains('..')) {
            throw "Ruta de evidencia insegura: '$relative'."
        }
        if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
            throw "SHA-256 ausente o inválido para '$relative'."
        }
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $runDirectory $relative))
        if (-not $fullPath.StartsWith($basePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "La evidencia sale de la carpeta de ejecución: '$relative'."
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "No existe la evidencia requerida: '$relative'."
        }
        $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Hash incorrecto para '$relative'."
        }
    }

    $manifest.status = 'PASS'
    $manifest | Add-Member -NotePropertyName finalized_utc `
        -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o')) -Force
    $encoded = $manifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText(
        $resolvedManifest,
        $encoded + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($false))
    )
    Write-Host "PASS registrado tras verificar archivos y hashes: $resolvedManifest"
    return
}

if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
    throw '-ManifestPath solo se usa junto con -RequestPass.'
}
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = 'RUN-{0}-RESCUE-PILOT' -f
        [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')
}

$androidCount = Get-ConnectedAndroidCount
$createdAt = [DateTimeOffset]::UtcNow
$runDirectory = Join-Path $OutputDirectory $RunId
if (Test-Path -LiteralPath $runDirectory) {
    throw "La ejecución ya existe y no se sobrescribirá: $runDirectory"
}
[System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null

$status = if ($androidCount -ge 3) { 'PENDING' } else { 'BLOCKED' }
$manifest = [ordered]@{
    schema_version = 1
    run_id = $RunId
    created_utc = $createdAt.ToString('o')
    status = $status
    commit = 'PENDING'
    build = 'PENDING'
    privacy = 'No PII, serials, MAC, peer IDs, keys, real coordinates or real messages'
    tools = [ordered]@{
        adb = Test-Tool 'adb'
        flutter = Test-Tool 'flutter'
        git = Test-Tool 'git'
        python = Test-Tool 'python'
        java = Test-Tool 'java'
        xcodebuild = Test-Tool 'xcodebuild'
    }
    preflight = [ordered]@{
        connected_android_count = $androidCount
        flutter_run_touched = $false
        physical_checks_executed = $false
    }
    hardware = [ordered]@{
        android_devices = if ($androidCount -ge 3) { 'OBSERVED_NOT_CONFIRMED' } else { 'BLOCKED' }
        iphone_and_mac = 'PENDING'
        bitle_anchors = 'PENDING'
        raspberry_pi_bluez = 'PENDING'
        meshtastic_pair = 'PENDING'
        authorized_lora_pair = 'PENDING'
    }
    required_scenarios = $requiredScenarios
    criteria_confirmed = @()
    first_failed_criterion = 'PENDING'
    evidence = @()
    operator_attestation = 'PENDING'
}
$manifestFile = Join-Path $runDirectory 'manifest.json'
[System.IO.File]::WriteAllText(
    $manifestFile,
    (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
    (New-Object System.Text.UTF8Encoding($false))
)

$report = @"
# Reporte de piloto del equipo de rescate

- Run ID: ``$RunId``
- Creado UTC: ``$($createdAt.ToString('o'))``
- Estado inicial: **$status**
- Commit/build: ``PENDING``
- Primer criterio incumplido: ``PENDING``

## Inventario por alias

``PENDING``. No incluya seriales, MAC, peer IDs, claves ni nombres personales.

## Escenarios y evidencia

Registre roster, triage, casos, clusters, zonas, authority, GeoJSON y cada gate
P0 por separado, con control negativo, resultado, archivo y SHA-256.

## Gates físicos pendientes

- iPhone + Mac/Xcode: ``PENDING``
- anclas Bitle y Raspberry Pi/BlueZ: ``PENDING``
- pareja Meshtastic: ``PENDING``
- pareja LoRa autorizada: ``PENDING``

Este preflight no ejecutó RF, no tocó ``flutter run`` y no declara PASS.
"@
[System.IO.File]::WriteAllText(
    (Join-Path $runDirectory 'report.md'),
    $report + [Environment]::NewLine,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Preflight creado: $runDirectory"
Write-Host "Android conectados (sin registrar seriales): $androidCount"
Write-Host "Estado inicial: $status"
