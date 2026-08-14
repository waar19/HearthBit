[CmdletBinding()]
param(
    [ValidateSet("all", "kotlin", "dart", "python", "swift", "firmware")]
    [string[]] $Target = @("all")
)

$ErrorActionPreference = "Stop"
$Repository = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$RunAll = $Target -contains "all"
$FlutterCommand = Get-Command "flutter" -ErrorAction SilentlyContinue
if ($null -eq $FlutterCommand) {
    $LocalProperties = Join-Path $Repository "app\android\local.properties"
    if (Test-Path $LocalProperties) {
        $FlutterSdk = (Get-Content $LocalProperties |
            Where-Object { $_ -like "flutter.sdk=*" } |
            Select-Object -First 1).Substring("flutter.sdk=".Length)
        $FlutterSdk = $FlutterSdk -replace "\\\\", "\"
        $FlutterCandidate = Join-Path $FlutterSdk "bin\flutter.bat"
        if (Test-Path $FlutterCandidate) {
            $FlutterCommand = $FlutterCandidate
        }
    }
}
if (-not $env:JAVA_HOME) {
    $BundledJava = "C:\Program Files\Android\Android Studio\jbr"
    if (Test-Path (Join-Path $BundledJava "bin\java.exe")) {
        $env:JAVA_HOME = $BundledJava
    }
}
$OnMacOS = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::OSX
)

function Invoke-InDirectory {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [scriptblock] $Command
    )
    Push-Location $Path
    try {
        & $Command
        if ($LASTEXITCODE -ne 0) {
            throw "El comando fallo con codigo $LASTEXITCODE en $Path"
        }
    }
    finally {
        Pop-Location
    }
}

python (Join-Path $PSScriptRoot "generate_firmware_header.py") --check
if ($LASTEXITCODE -ne 0) {
    throw "conformance_vectors.h no coincide con los fixtures neutrales"
}
python -m pytest (Join-Path $PSScriptRoot "test_firmware_header.py")
if ($LASTEXITCODE -ne 0) {
    throw "La cobertura del header firmware no coincide con el manifiesto"
}

if ($RunAll -or $Target -contains "kotlin") {
    Invoke-InDirectory (Join-Path $Repository "app\android") {
        & ".\gradlew.bat" ":app:testDebugUnitTest" `
            "--tests" "com.hearthbit.app.mesh.ConformanceFixtureTest"
    }
}

if ($RunAll -or $Target -contains "dart") {
    if ($null -eq $FlutterCommand) {
        throw "No se encontro Flutter en PATH ni en app/android/local.properties"
    }
    Invoke-InDirectory (Join-Path $Repository "app") {
        & $FlutterCommand "test" "test/conformance_fixtures_test.dart"
    }
}

if ($RunAll -or $Target -contains "python") {
    Invoke-InDirectory (Join-Path $Repository "relay") {
        $env:PYTHONPATH = (Join-Path (Get-Location) "src")
        & "python" "-m" "pytest" "tests/test_conformance_fixtures.py"
    }
}

if ($RunAll -or $Target -contains "swift") {
    if (-not $OnMacOS) {
        Write-Warning "Swift XCTest requiere macOS; runner preparado pero no ejecutado."
    }
    else {
        Invoke-InDirectory (Join-Path $Repository "app\ios") {
            & "xcodebuild" "test" "-workspace" "Runner.xcworkspace" `
                "-scheme" "Runner" "-sdk" "iphonesimulator" `
                "-destination" "platform=iOS Simulator,OS=latest,name=iPhone 16" `
                "CODE_SIGNING_ALLOWED=NO"
        }
    }
}

if ($RunAll -or $Target -contains "firmware") {
    $Idf = Get-Command "idf.py" -ErrorAction SilentlyContinue
    if ($null -eq $Idf) {
        Write-Warning "ESP-IDF no esta disponible; se valido el header generado."
    }
    else {
        Invoke-InDirectory (Join-Path $Repository "firmware\anchor-node") {
            & "idf.py" "build"
        }
        Write-Host "El self-test C se ejecuta al arrancar el firmware."
    }
}
