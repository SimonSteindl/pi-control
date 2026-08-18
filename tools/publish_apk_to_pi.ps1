param(
    [string]$PiHost = 'stoney22@192.168.0.123'
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $workspaceRoot 'pubspec.yaml'
$builtApkPath = Join-Path $workspaceRoot 'build\app\outputs\flutter-apk\app-release.apk'

$versionLine = Select-String -LiteralPath $pubspecPath -Pattern '^version:\s*([^+\s]+)' | Select-Object -First 1
if (-not $versionLine) {
    throw 'Version konnte nicht aus pubspec.yaml gelesen werden.'
}

$version = $versionLine.Matches[0].Groups[1].Value
$fileName = "Pi-Control-$version.apk"
$localReleaseDirectory = Join-Path $workspaceRoot 'artifacts'
$localReleasePath = Join-Path $localReleaseDirectory $fileName
$remoteTemporaryPath = "/tmp/$fileName"
$remoteReleaseDirectory = '/mnt/pishare/App/.apk'
$remoteReleasePath = "$remoteReleaseDirectory/$fileName"

if (-not (Test-Path -LiteralPath $builtApkPath -PathType Leaf)) {
    throw 'Release-APK fehlt. Zuerst flutter build apk --release ausführen.'
}

New-Item -ItemType Directory -Force -Path $localReleaseDirectory | Out-Null
Copy-Item -LiteralPath $builtApkPath -Destination $localReleasePath -Force

& scp -- $localReleasePath "${PiHost}:$remoteTemporaryPath"
if ($LASTEXITCODE -ne 0) {
    throw 'Übertragung der APK zum Raspberry Pi fehlgeschlagen.'
}

$remoteCommand = "test -d '$remoteReleaseDirectory' && sudo install -o stoney22 -g stoney22 -m 0664 '$remoteTemporaryPath' '$remoteReleasePath' && stat -c '%n %s bytes' '$remoteReleasePath' && sha256sum '$remoteReleasePath' && rm -f '$remoteTemporaryPath'"
& ssh -tt $PiHost $remoteCommand
if ($LASTEXITCODE -ne 0) {
    throw "Veröffentlichung fehlgeschlagen. Der bestehende Ordner $remoteReleaseDirectory wurde nicht verändert oder fehlt."
}

Write-Host "APK veröffentlicht: $remoteReleasePath"
