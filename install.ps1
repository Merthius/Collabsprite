$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\output\Collabsprite.aseprite-extension'))
$extensionRoot = Join-Path $env:APPDATA 'Aseprite\extensions'
$extensionTarget = Join-Path $extensionRoot 'pixelkollab-native'
if (-not (Test-Path -LiteralPath $package)) { throw 'Zuerst build.ps1 ausfuehren.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($package)
try {
$first = $archive.Entries | Where-Object { [IO.Path]::GetFileName($_.FullName) -eq 'package.json' } | Select-Object -First 1
if ($first.FullName -ne 'package.json') { throw 'Ungueltige Reihenfolge der Installerdateien.' }
$reader = [IO.StreamReader]::new($first.Open())
try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
if ($manifest.name -ne 'pixelkollab-native') { throw 'Falsches Erweiterungspaket.' }
if (Test-Path -LiteralPath $extensionTarget) {
    $backupRoot = Join-Path $PSScriptRoot 'install-backups'
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    $backupTarget = Join-Path $backupRoot ('pixelkollab-native-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $extensionTarget -Destination $backupTarget -Recurse
    Write-Host "Bisherige eigene Erweiterung gesichert: $backupTarget"
}
New-Item -ItemType Directory -Force -Path $extensionTarget | Out-Null
foreach ($entry in $archive.Entries) {
    if ($entry.FullName -match '(^|/)(data|__pref.lua|__info.json)(/|$)') { throw 'Nutzerdaten im Installer.' }
    $destination = [IO.Path]::GetFullPath((Join-Path $extensionTarget $entry.FullName))
    if (-not $destination.StartsWith($extensionTarget + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Ungueltiger Archivpfad.' }
    New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($destination)) | Out-Null
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$destination,$true)
}
# Aseprite requires this inventory for a future native update/uninstall.
# Never include data/ or __pref.lua: they belong to the user.
$inventory = @{ installedFiles = @($archive.Entries | ForEach-Object FullName) }
$inventoryJson = $inventory | ConvertTo-Json -Depth 3
[IO.File]::WriteAllText((Join-Path $extensionTarget '__info.json'),$inventoryJson,[Text.UTF8Encoding]::new($false))
} finally { $archive.Dispose() }
Write-Host "Collabsprite installiert (kompatibles Update): $extensionTarget"
Write-Host 'Alle Aseprite-Instanzen nach dem Speichern bitte neu starten. Danach: Ansicht > Collabsprite.'
Write-Host 'Andere Erweiterungen und eigene Bilddateien wurden nicht geaendert.'
