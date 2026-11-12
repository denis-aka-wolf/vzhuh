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

    & $flutter.Source analyze
    if ($LASTEXITCODE -ne 0) {
        throw "flutter analyze failed with exit code $LASTEXITCODE."
    }

    & $flutter.Source test
    if ($LASTEXITCODE -ne 0) {
        throw "flutter test failed with exit code $LASTEXITCODE."
    }

    & $flutter.Source build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build windows failed with exit code $LASTEXITCODE."
    }

    $releaseDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
    $executable = Join-Path $releaseDirectory 'vzhuh.exe'
    $assetsDirectory = Join-Path $releaseDirectory 'data\flutter_assets'
    $flutterLibrary = Join-Path $releaseDirectory 'flutter_windows.dll'

    foreach ($requiredPath in @($executable, $assetsDirectory, $flutterLibrary)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required build output is missing: $requiredPath"
        }
    }

    $pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
    $versionLine = $pubspec | Where-Object { $_ -match '^version:\s*(.+)$' } | Select-Object -First 1
    $version = if ($versionLine -match '^version:\s*(.+)$') {
        $Matches[1].Trim()
    }
    else {
        'unversioned'
    }
    $safeVersion = $version -replace '[^A-Za-z0-9._-]', '-'
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $packageName = "Vzhuh-$safeVersion-$timestamp"
    $outputDirectory = Join-Path $projectRoot 'out'
    $stagingDirectory = Join-Path $outputDirectory ".$packageName-staging"
    $packageDirectory = Join-Path $outputDirectory $packageName

    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    if ((Test-Path -LiteralPath $stagingDirectory) -or
        (Test-Path -LiteralPath $packageDirectory)) {
        throw "Output directory already exists; it will not be overwritten: $packageDirectory"
    }

    try {
        New-Item -ItemType Directory -Path $stagingDirectory | Out-Null
        Get-ChildItem -LiteralPath $releaseDirectory -Force |
            Copy-Item -Destination $stagingDirectory -Recurse -Force

        foreach ($relativePath in @(
                'vzhuh.exe',
                'flutter_windows.dll',
                'data\flutter_assets'
            )) {
            $copiedPath = Join-Path $stagingDirectory $relativePath
            if (-not (Test-Path -LiteralPath $copiedPath)) {
                throw "Required file was not copied: $relativePath"
            }
        }

        @(
            "Vzhuh $version - Windows Release"
            "Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
            ''
            'This is a release build of the current MVP.'
            'The connection protocol is not encrypted and does not authenticate peers.'
            'Use only in an isolated test network. Do not expose the listening port to the internet.'
        ) | Set-Content -LiteralPath (Join-Path $stagingDirectory 'BUILD-INFO.txt') -Encoding UTF8

        Move-Item -LiteralPath $stagingDirectory -Destination $packageDirectory
    }
    catch {
        if (Test-Path -LiteralPath $stagingDirectory) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
        }
        throw
    }

    Write-Output "Windows Release package created: $packageDirectory"
}
finally {
    Pop-Location
}
