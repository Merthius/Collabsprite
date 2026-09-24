$ErrorActionPreference = 'Stop'
$extensionSource = Join-Path $PSScriptRoot 'extension'
$extensionRoot = Join-Path $env:APPDATA 'Aseprite\extensions'
$extensionTarget = Join-Path $extensionRoot 'pixelkollab-native'
if (-not (Test-Path -LiteralPath (Join-Path $extensionSource 'package.json'))) { throw 'Erweiterungsdateien fehlen.' }
if (Test-Path -LiteralPath $extensionTarget) {
    $backupRoot = Join-Path $PSScriptRoot 'install-backups'
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    $backupTarget = Join-Path $backupRoot ('pixelkollab-native-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $extensionTarget -Destination $backupTarget -Recurse
    Write-Host "Bisherige eigene Erweiterung gesichert: $backupTarget"
}
New-Item -ItemType Directory -Force -Path $extensionTarget | Out-Null
$oldProbe = Join-Path $extensionTarget 'Probe.exe'
if (Test-Path -LiteralPath $oldProbe) { Remove-Item -LiteralPath $oldProbe -Force }
$oldLauncher = Join-Path $extensionTarget 'Launcher.ps1'
if (Test-Path -LiteralPath $oldLauncher) { Remove-Item -LiteralPath $oldLauncher -Force }
Get-ChildItem -LiteralPath $extensionSource -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $extensionTarget $_.Name) -Force
}
foreach ($name in @('server.mjs','core.mjs','network.mjs','firewall.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $extensionTarget $name) -Force
}
$moduleTarget = Join-Path $extensionTarget 'node_modules'
New-Item -ItemType Directory -Force -Path $moduleTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'node_modules\ws') -Destination $moduleTarget -Recurse -Force
Write-Host "Collabsprite installiert (kompatibles Update): $extensionTarget"
Write-Host 'Alle Aseprite-Instanzen nach dem Speichern bitte neu starten. Danach: Ansicht > Collabsprite...'
Write-Host 'Andere Erweiterungen und eigene Bilddateien wurden nicht geaendert.'
