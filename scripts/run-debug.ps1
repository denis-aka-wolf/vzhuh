$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -eq $flutter) {
        throw 'Flutter was not found in PATH. Install the Flutter SDK and reopen PowerShell.'
    }

    & $flutter.Source pub get
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed with exit code $LASTEXITCODE."
    }

    & $flutter.Source run --debug -d windows
    if ($LASTEXITCODE -ne 0) {
        throw "flutter run failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
