#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidatePattern('^RUN-[A-Z0-9][A-Z0-9_-]{5,80}$')]
    [string]$RunId,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\artifacts\rescue-pilot'),

    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ManifestPath,

    [Alias('RequestPass')]
    [switch]$RequestReview
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
    'P0-OPTICAL-TRUST',
    'P0-SOS-CLOCK-01',
    'P0-SOS-BATTERY-01',
    'P0-BT-RECOVERY-01',
    'P0-RESCUE-RESTART-01',
    'P0-IOS-FORCEQUIT-01',
    'P0-RADAR-30M-01',
    'P0-BEACON-HOP-01',
    'P0-MESHTASTIC-QUEUE-01',
    'P0-LORA-ATOMIC-01',
    'P0-SONAR-NOISE-01'
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

function Invoke-ToolCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [int]$TimeoutSeconds = 5
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) {
        return [pscustomobject]@{
            available = $false
            completed = $false
            exit_code = $null
            output = ''
        }
    }

    $path = if ([string]::IsNullOrWhiteSpace([string]$command.Source)) {
        [string]$command.Path
    } else {
        [string]$command.Source
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    if ([System.IO.Path]::GetExtension($path) -in @('.bat', '.cmd')) {
        $startInfo.FileName = $env:ComSpec
        $startInfo.Arguments = "/d /c `"`"$path`" $Arguments`""
    } else {
        $startInfo.FileName = $path
        $startInfo.Arguments = $Arguments
    }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "No se pudo iniciar $Name."
        }
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            return [pscustomobject]@{
                available = $true
                completed = $false
                exit_code = $null
                output = ''
            }
        }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        return [pscustomobject]@{
            available = $true
            completed = $true
            exit_code = $process.ExitCode
            output = ($stdout + [Environment]::NewLine + $stderr).Trim()
        }
    } catch {
        return [pscustomobject]@{
            available = $true
            completed = $false
            exit_code = $null
            output = ''
        }
    } finally {
        $process.Dispose()
    }
}

function Get-ToolInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Arguments
    )
    $capture = Invoke-ToolCapture -Name $Name -Arguments $Arguments
    $version = $null
    if ($capture.completed -and $capture.exit_code -eq 0) {
        $version = @($capture.output -split '\r?\n' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -First 1)
        if ($version.Count -eq 1) {
            $version = [string]$version[0].Trim()
        } else {
            $version = $null
        }
    }
    return [ordered]@{
        available = [bool]$capture.available
        version = $version
        query = if (-not $capture.available) {
            'UNAVAILABLE'
        } elseif (-not $capture.completed) {
            'TIMEOUT_OR_START_FAILURE'
        } elseif ($capture.exit_code -ne 0) {
            'VERSION_QUERY_FAILED'
        } else {
            'RECORDED'
        }
    }
}

function Get-ConnectedAndroidCount {
    $capture = Invoke-ToolCapture -Name 'adb' -Arguments 'devices'
    if (-not $capture.completed -or $capture.exit_code -ne 0) {
        return 0
    }
    return @($capture.output -split '\r?\n' |
        Where-Object { $_ -match "`tdevice$" }).Count
}

function Assert-ReviewPackage {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedManifest = (Resolve-Path -LiteralPath $Path).Path
    $runDirectory = Split-Path -Parent $resolvedManifest
    $manifest = Get-Content -LiteralPath $resolvedManifest -Raw |
        ConvertFrom-Json

    if ([int]$manifest.schema_version -ne 2) {
        throw 'Versión de manifiesto no soportada.'
    }
    if ([string]$manifest.status -eq 'PASS') {
        throw 'PASS solo puede existir en una revisión independiente externa.'
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
            throw "Revisión bloqueada: hardware '$hardwareName' no está CONFIRMED."
        }
    }

    $documented = @($manifest.criteria_documented)
    foreach ($scenario in $requiredScenarios) {
        if ($scenario -notin $documented) {
            throw "Revisión bloqueada: falta documentar el escenario '$scenario'."
        }
    }

    $evidence = @($manifest.evidence)
    $categories = @($evidence | ForEach-Object { [string]$_.category })
    foreach ($category in $requiredEvidenceCategories) {
        if ($category -notin $categories) {
            throw "Revisión bloqueada: falta evidencia de categoría '$category'."
        }
    }

    $basePath = [System.IO.Path]::GetFullPath($runDirectory) +
        [System.IO.Path]::DirectorySeparatorChar
    $usedPaths = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $usedHashes = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $scenariosWithEvidence = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::Ordinal
    )
    foreach ($item in $evidence) {
        $scenario = [string]$item.scenario
        $category = [string]$item.category
        $relative = [string]$item.path
        $expectedHash = ([string]$item.sha256).ToLowerInvariant()
        if ($scenario -notin $requiredScenarios) {
            throw "Escenario de evidencia desconocido: '$scenario'."
        }
        if ($category -notin $requiredEvidenceCategories) {
            throw "Categoría de evidencia desconocida: '$category'."
        }
        if ([System.IO.Path]::IsPathRooted($relative) -or
            '..' -in @($relative -split '[\\/]')) {
            throw "Ruta de evidencia insegura: '$relative'."
        }
        if (-not $usedPaths.Add($relative)) {
            throw "Un archivo no puede cubrir escenarios o categorías distintas: '$relative'."
        }
        if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
            throw "SHA-256 ausente o inválido para '$relative'."
        }
        if (-not $usedHashes.Add($expectedHash)) {
            throw "Un mismo contenido no puede cubrir evidencia distinta: '$relative'."
        }
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $runDirectory $relative))
        if (-not $fullPath.StartsWith(
            $basePath,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "La evidencia sale de la carpeta de ejecución: '$relative'."
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "No existe la evidencia requerida: '$relative'."
        }
        $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).
            Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Hash incorrecto para '$relative'."
        }
        [void]$scenariosWithEvidence.Add($scenario)
    }
    foreach ($scenario in $requiredScenarios) {
        if (-not $scenariosWithEvidence.Contains($scenario)) {
            throw "Revisión bloqueada: '$scenario' no tiene evidencia propia."
        }
    }

    $manifest.status = 'READY_FOR_REVIEW'
    $manifest | Add-Member -NotePropertyName review_package_checked_utc `
        -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o')) -Force
    $encoded = $manifest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText(
        $resolvedManifest,
        $encoded + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($false))
    )
    Write-Host "Paquete listo para revisión independiente: $resolvedManifest"
    Write-Host 'El script nunca registra PASS.'
}

if ($RequestReview) {
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        throw '-RequestReview requiere -ManifestPath.'
    }
    Assert-ReviewPackage -Path $ManifestPath
    return
}

if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
    throw '-ManifestPath solo se usa junto con -RequestReview.'
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

$gitCommit = Invoke-ToolCapture -Name 'git' -Arguments 'rev-parse --verify HEAD'
$commit = if ($gitCommit.completed -and $gitCommit.exit_code -eq 0 -and
    $gitCommit.output -match '^[0-9a-fA-F]{40}$') {
    $gitCommit.output.ToLowerInvariant()
} else {
    'PENDING'
}
$status = if ($androidCount -ge 3) { 'PENDING' } else { 'BLOCKED' }
$manifest = [ordered]@{
    schema_version = 2
    run_id = $RunId
    created_utc = $createdAt.ToString('o')
    status = $status
    commit = $commit
    build = 'PENDING'
    privacy = 'No PII, serials, MAC, peer IDs, keys, real coordinates or real messages'
    tools = [ordered]@{
        adb = Get-ToolInfo -Name 'adb' -Arguments 'version'
        flutter = Get-ToolInfo -Name 'flutter' -Arguments '--version'
        git = Get-ToolInfo -Name 'git' -Arguments '--version'
        python = Get-ToolInfo -Name 'python' -Arguments '--version'
        java = Get-ToolInfo -Name 'java' -Arguments '-version'
        xcodebuild = Get-ToolInfo -Name 'xcodebuild' -Arguments '-version'
    }
    preflight = [ordered]@{
        connected_android_count = $androidCount
        flutter_run_touched = $false
        physical_checks_executed = $false
    }
    hardware = [ordered]@{
        android_devices = if ($androidCount -ge 3) {
            'OBSERVED_COUNT_ONLY'
        } else {
            'BLOCKED'
        }
        iphone_and_mac = 'PENDING'
        bitle_anchors = 'PENDING'
        raspberry_pi_bluez = 'PENDING'
        meshtastic_pair = 'PENDING'
        authorized_lora_pair = 'PENDING'
    }
    required_scenarios = $requiredScenarios
    required_evidence_categories = $requiredEvidenceCategories
    criteria_documented = @()
    first_failed_criterion = 'PENDING'
    evidence = @()
    independent_review = [ordered]@{
        required = $true
        recorded_by_script = $false
        external_record = 'PENDING'
    }
}
$manifestFile = Join-Path $runDirectory 'manifest.json'
[System.IO.File]::WriteAllText(
    $manifestFile,
    (($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine),
    (New-Object System.Text.UTF8Encoding($false))
)

$report = @"
# Reporte de piloto del equipo de rescate

- Run ID: ``$RunId``
- Creado UTC: ``$($createdAt.ToString('o'))``
- Estado inicial: **$status**
- Commit: ``$commit``
- Build: ``PENDING``
- Primer criterio incumplido: ``PENDING``

## Inventario por alias

``PENDING``. No incluya seriales, MAC, peer IDs, claves ni nombres personales.

## Escenarios y evidencia

Registre cada escenario y cada gate P0 por separado. Cada uno requiere un
archivo propio, saneado y con SHA-256. Un archivo no puede cubrir dos categorías
o escenarios, aunque se copie con otro nombre.

## Gates físicos pendientes

- iPhone + Mac/Xcode: ``PENDING``
- anclas Bitle y Raspberry Pi/BlueZ: ``PENDING``
- pareja Meshtastic: ``PENDING``
- pareja LoRa autorizada: ``PENDING``

Este preflight no ejecutó RF, no tocó ``flutter run`` y no declara PASS.
El máximo automático es ``READY_FOR_REVIEW``. Solo una revisión independiente,
registrada fuera de este script, puede emitir una decisión PASS.
"@
[System.IO.File]::WriteAllText(
    (Join-Path $runDirectory 'report.md'),
    $report + [Environment]::NewLine,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Preflight creado: $runDirectory"
Write-Host "Android conectados (sin registrar seriales): $androidCount"
Write-Host "Estado inicial: $status"
