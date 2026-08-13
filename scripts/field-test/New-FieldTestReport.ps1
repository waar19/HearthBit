#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$CaptureMetadataPath,

    [ValidateSet('PENDING', 'PASS', 'FAIL', 'BLOCKED')]
    [string]$Result = 'PENDING',

    [ValidateSet(
        'OPERATOR_PENDING',
        'ALL_CRITERIA_MET',
        'DELIVERY_MISSING',
        'DUPLICATE_DELIVERY',
        'UNEXPECTED_CLEAR_TEXT',
        'LOG_ERROR',
        'TOPOLOGY_NOT_PROVEN',
        'ROLE_POLICY_VIOLATION',
        'HARDWARE_UNAVAILABLE',
        'INTERACTION_REQUIRED'
    )]
    [string]$ReasonCode = 'OPERATOR_PENDING',

    [ValidatePattern('^D1-[A-Z0-9][A-Z0-9_-]{5,95}$')]
    [string[]]$ObservedIdentifier = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Result -eq 'PASS' -and $ReasonCode -ne 'ALL_CRITERIA_MET') {
    throw 'PASS requiere ReasonCode=ALL_CRITERIA_MET.'
}
if ($Result -ne 'PASS' -and $ReasonCode -eq 'ALL_CRITERIA_MET') {
    throw 'ALL_CRITERIA_MET solo puede usarse con PASS.'
}
if ($Result -eq 'PENDING' -and $ReasonCode -ne 'OPERATOR_PENDING') {
    throw 'PENDING requiere ReasonCode=OPERATOR_PENDING.'
}
if ($Result -ne 'PENDING' -and $ReasonCode -eq 'OPERATOR_PENDING') {
    throw 'OPERATOR_PENDING solo puede usarse con PENDING.'
}

$metadataPath = (Resolve-Path -LiteralPath $CaptureMetadataPath).Path
$captureDirectory = Split-Path -Parent $metadataPath
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$requiredProperties = @(
    'schema_version',
    'run_id',
    'case_id',
    'node_alias',
    'capture_started_utc',
    'capture_finished_utc',
    'adb_filter',
    'log_file',
    'log_sha256',
    'privacy'
)
foreach ($property in $requiredProperties) {
    if ($null -eq $metadata.$property -or [string]::IsNullOrWhiteSpace([string]$metadata.$property)) {
        throw "Falta la propiedad requerida '$property' en capture.json."
    }
}
if ([int]$metadata.schema_version -ne 1) {
    throw "Versión de capture.json no soportada: $($metadata.schema_version)"
}
if ([string]$metadata.run_id -notmatch '^[A-Z0-9][A-Z0-9_-]{5,63}$') {
    throw 'run_id no cumple el formato seguro esperado.'
}
if ([string]$metadata.case_id -notmatch '^D1-[A-Z0-9]+(?:-[A-Z0-9]+)*$') {
    throw 'case_id no cumple el formato seguro esperado.'
}
if ([string]$metadata.node_alias -notmatch '^[A-Z0-9][A-Z0-9-]{1,31}$') {
    throw 'node_alias no cumple el formato seguro esperado.'
}
if ([string]$metadata.adb_filter -ne 'HearthBitMesh:V *:S') {
    throw 'adb_filter no coincide con el filtro seguro esperado.'
}
if ([string]$metadata.privacy -ne
    'MAC, Bluetooth names, packet prefixes and peer identifiers redacted before writing'
) {
    throw 'La declaración de privacidad de capture.json no coincide con la esperada.'
}
if ([System.IO.Path]::GetFileName([string]$metadata.log_file) -ne [string]$metadata.log_file) {
    throw 'log_file debe ser un nombre de archivo, no una ruta.'
}

$logPath = Join-Path $captureDirectory ([string]$metadata.log_file)
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    throw "No existe el log saneado declarado: $logPath"
}
$actualHash = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedHash = ([string]$metadata.log_sha256).ToLowerInvariant()
if ($actualHash -ne $expectedHash) {
    throw 'El hash del log no coincide con capture.json; no se generó el informe.'
}

$generatedAt = [DateTimeOffset]::UtcNow
$reportName = 'report-{0}.md' -f $generatedAt.ToString('yyyyMMddTHHmmssfffZ')
$reportPath = Join-Path $captureDirectory $reportName
if (Test-Path -LiteralPath $reportPath) {
    throw "El informe ya existe y no se sobrescribirá: $reportPath"
}

$identifierLines = if ($ObservedIdentifier.Count -eq 0) {
    '- Ninguno declarado.'
}
else {
    ($ObservedIdentifier | Sort-Object -Unique | ForEach-Object { "- ``$_``" }) -join [Environment]::NewLine
}

$report = @"
# Informe de prueba de campo D1

- Run ID: ``$($metadata.run_id)``
- Caso: ``$($metadata.case_id)``
- Nodo: ``$($metadata.node_alias)``
- Captura iniciada (UTC): ``$($metadata.capture_started_utc)``
- Captura finalizada (UTC): ``$($metadata.capture_finished_utc)``
- Informe generado (UTC): ``$($generatedAt.ToString('o'))``
- Resultado declarado por el operador: **$Result**
- Código de motivo: ``$ReasonCode``

## Identificadores observados

$identifierLines

## Evidencia automatizada

- Log: ``$($metadata.log_file)``
- SHA-256: ``$actualHash``
- Filtro adb: ``$($metadata.adb_filter)``
- Privacidad: $($metadata.privacy).

## Alcance

El script verifica la integridad del log saneado y registra la decisión del
operador. No infiere entrega física, ausencia de enlace directo, cifrado
extremo a extremo ni cumplimiento de roles. Compare esta evidencia con los
criterios PASS/FAIL del caso correspondiente en ``docs/field-test.md``.
"@

[System.IO.File]::WriteAllText(
    $reportPath,
    $report + [Environment]::NewLine,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Informe: $reportPath"
