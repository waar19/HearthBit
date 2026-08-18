#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pilotScript = Join-Path $PSScriptRoot 'New-RescuePilotRun.ps1'
$root = Join-Path ([System.IO.Path]::GetTempPath()) (
    'hearthbit-rescue-pilot-selftest-' + [Guid]::NewGuid().ToString('N')
)
[System.IO.Directory]::CreateDirectory($root) | Out-Null

function Save-Json {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    [System.IO.File]::WriteAllText(
        $Path,
        (($Value | ConvertTo-Json -Depth 10) + [Environment]::NewLine),
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function New-CompletePackage {
    param([Parameter(Mandatory = $true)][string]$RunId)

    & $pilotScript -RunId $RunId -OutputDirectory $root | Out-Null
    $runDirectory = Join-Path $root $RunId
    $manifestPath = Join-Path $runDirectory 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($property in $manifest.hardware.PSObject.Properties) {
        $property.Value = 'CONFIRMED'
    }
    $manifest.criteria_documented = @($manifest.required_scenarios)
    $evidence = @()
    for ($index = 0; $index -lt $manifest.required_scenarios.Count; $index++) {
        $scenario = [string]$manifest.required_scenarios[$index]
        $category = [string]$manifest.required_evidence_categories[
            $index % $manifest.required_evidence_categories.Count
        ]
        $relative = 'evidence-{0:D2}.txt' -f $index
        $fullPath = Join-Path $runDirectory $relative
        [System.IO.File]::WriteAllText(
            $fullPath,
            "evidencia sintética saneada: $scenario",
            (New-Object System.Text.UTF8Encoding($false))
        )
        $evidence += [pscustomobject]@{
            scenario = $scenario
            category = $category
            path = $relative
            sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).
                Hash.ToLowerInvariant()
        }
    }
    $manifest.evidence = $evidence
    Save-Json -Path $manifestPath -Value $manifest
    return $manifestPath
}

function Assert-ReviewFails {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    $failed = $false
    try {
        & $pilotScript -ManifestPath $ManifestPath -RequestReview | Out-Null
    } catch {
        $failed = $true
    }
    if (-not $failed) {
        throw "Se esperaba rechazo para '$ManifestPath'."
    }
    $status = [string](Get-Content -LiteralPath $ManifestPath -Raw |
        ConvertFrom-Json).status
    if ($status -in @('READY_FOR_REVIEW', 'PASS')) {
        throw "El paquete rechazado terminó en estado inseguro '$status'."
    }
}

try {
    $incompletePath = New-CompletePackage -RunId 'RUN-SELFTEST-INCOMPLETE'
    $incomplete = Get-Content -LiteralPath $incompletePath -Raw |
        ConvertFrom-Json
    $incomplete.criteria_documented = @(
        $incomplete.criteria_documented |
            Select-Object -SkipLast 1
    )
    Save-Json -Path $incompletePath -Value $incomplete
    Assert-ReviewFails -ManifestPath $incompletePath

    $duplicatePath = New-CompletePackage -RunId 'RUN-SELFTEST-DUPLICATE'
    $duplicate = Get-Content -LiteralPath $duplicatePath -Raw |
        ConvertFrom-Json
    $duplicateDirectory = Split-Path -Parent $duplicatePath
    [System.IO.File]::WriteAllBytes(
        (Join-Path $duplicateDirectory $duplicate.evidence[1].path),
        [System.IO.File]::ReadAllBytes(
            (Join-Path $duplicateDirectory $duplicate.evidence[0].path)
        )
    )
    $duplicate.evidence[1].sha256 = $duplicate.evidence[0].sha256
    Save-Json -Path $duplicatePath -Value $duplicate
    Assert-ReviewFails -ManifestPath $duplicatePath

    $completePath = New-CompletePackage -RunId 'RUN-SELFTEST-COMPLETE'
    # El alias histórico debe ser incapaz de producir PASS.
    & $pilotScript -ManifestPath $completePath -RequestPass | Out-Null
    $complete = Get-Content -LiteralPath $completePath -Raw |
        ConvertFrom-Json
    if ([string]$complete.status -ne 'READY_FOR_REVIEW') {
        throw "Se esperaba READY_FOR_REVIEW y se obtuvo '$($complete.status)'."
    }
    if ([string]$complete.status -eq 'PASS') {
        throw 'El script produjo PASS.'
    }

    Write-Host 'PASS self-test: incompleto rechazado.'
    Write-Host 'PASS self-test: evidencia duplicada rechazada.'
    Write-Host 'PASS self-test: paquete completo queda READY_FOR_REVIEW, nunca PASS.'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
