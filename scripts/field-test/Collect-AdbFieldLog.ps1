#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^D1-[A-Z0-9]+(?:-[A-Z0-9]+)*$')]
    [string]$CaseId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Z0-9][A-Z0-9_-]{5,63}$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Z0-9][A-Z0-9-]{1,31}$')]
    [string]$NodeAlias,

    [ValidateRange(10, 3600)]
    [int]$DurationSeconds = 180,

    [ValidatePattern('^[^\s"]+$')]
    [string]$DeviceSerial,

    [string]$AdbPath = 'adb',

    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\artifacts\field-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Protect-SensitiveText {
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $safe = $Text
    $safe = [regex]::Replace(
        $safe,
        '(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b',
        '[MAC_REDACTED]'
    )
    $safe = [regex]::Replace(
        $safe,
        '(?i)\baddress=[^\s,]+',
        'address=[REDACTED]'
    )
    $safe = [regex]::Replace(
        $safe,
        '(?i)(queue full for )[^\s,]+',
        '$1[REDACTED]'
    )
    $safe = [regex]::Replace(
        $safe,
        '(?im)\b(nickname|deviceName|local_name|name)=.*$',
        '$1=[NAME_REDACTED]'
    )
    $safe = [regex]::Replace(
        $safe,
        '(?i)\bprefix=[0-9a-f]+',
        'prefix=[HEX_REDACTED]'
    )
    $safe = [regex]::Replace(
        $safe,
        '(?i)\bsender=[0-9a-f]{8,64}\b',
        'sender=[PEER_REDACTED]'
    )
    $safe = [regex]::Replace(
        $safe,
        '(?i)\b(from|anchor|to) [0-9a-f]{8,64}\b',
        '$1 [PEER_REDACTED]'
    )
    return $safe
}

if ([string]::IsNullOrWhiteSpace($AdbPath)) {
    throw 'AdbPath no puede estar vacío.'
}

$startedAt = [DateTimeOffset]::UtcNow
$timestamp = $startedAt.ToString('yyyyMMddTHHmmssfffZ')
$captureName = '{0}-{1}-{2}-{3}' -f $timestamp, $CaseId, $RunId, $NodeAlias
$captureDirectory = Join-Path $OutputDirectory $captureName

if (Test-Path -LiteralPath $captureDirectory) {
    throw "La captura ya existe y no se sobrescribirá: $captureDirectory"
}

$process = New-Object System.Diagnostics.Process
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $AdbPath
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true

$arguments = New-Object System.Collections.Generic.List[string]
if ($PSBoundParameters.ContainsKey('DeviceSerial')) {
    $arguments.Add('-s')
    $arguments.Add($DeviceSerial)
}
$arguments.Add('logcat')
$arguments.Add('-v')
$arguments.Add('threadtime')
$arguments.Add('HearthBitMesh:V')
$arguments.Add('*:S')
$startInfo.Arguments = ($arguments -join ' ')
$process.StartInfo = $startInfo
$processStarted = $false

Write-Host "Capturando $CaseId en $NodeAlias durante $DurationSeconds s..."
Write-Host 'Realice ahora únicamente el caso indicado. La captura no limpia logcat ni modifica la aplicación.'

try {
    if (-not $process.Start()) {
        throw 'adb no pudo iniciarse.'
    }
    $processStarted = $true

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($DurationSeconds * 1000)

    if (-not $completed) {
        $process.Kill()
        $process.WaitForExit()
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($completed -and $process.ExitCode -ne 0) {
        $safeError = Protect-SensitiveText -Text $stderr
        throw "adb logcat terminó con código $($process.ExitCode): $safeError"
    }
}
catch {
    if ($processStarted -and -not $process.HasExited) {
        $process.Kill()
        $process.WaitForExit()
    }
    throw
}
finally {
    $process.Dispose()
}

$finishedAt = [DateTimeOffset]::UtcNow
$safeLog = Protect-SensitiveText -Text (($stdout, $stderr) -join [Environment]::NewLine)
$logFileName = 'adb-hearthbitmesh-sanitized.log'
$logPath = Join-Path $captureDirectory $logFileName
New-Item -ItemType Directory -Path $captureDirectory | Out-Null
[System.IO.File]::WriteAllText($logPath, $safeLog, (New-Object System.Text.UTF8Encoding($false)))
$logHash = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant()

$metadata = [ordered]@{
    schema_version = 1
    run_id = $RunId
    case_id = $CaseId
    node_alias = $NodeAlias
    capture_started_utc = $startedAt.ToString('o')
    capture_finished_utc = $finishedAt.ToString('o')
    duration_seconds = $DurationSeconds
    adb_filter = 'HearthBitMesh:V *:S'
    log_file = $logFileName
    log_sha256 = $logHash
    privacy = 'MAC, Bluetooth names, packet prefixes and peer identifiers redacted before writing'
}
$metadataPath = Join-Path $captureDirectory 'capture.json'
$metadataJson = $metadata | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText(
    $metadataPath,
    $metadataJson + [Environment]::NewLine,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Captura saneada: $logPath"
Write-Host "Metadatos: $metadataPath"
