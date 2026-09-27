# Detached update worker. Aseprite polls ResultPath instead of waiting for HTTPS.
param(
    [Parameter(Mandatory=$true)][string]$ResultPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*)?$')][string]$InstalledVersion,
    [string]$DownloadDirectory = ''
)
$ErrorActionPreference = 'Stop'
$partial = $null
function Report([string]$line) {
    $temporary = $ResultPath + '.tmp'
    [IO.File]::WriteAllText($temporary,$line,[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $ResultPath -Force
}
function FileHash([string]$path) {
    # Works in Windows PowerShell even with an inherited PowerShell 7 module path.
    $stream = [IO.File]::OpenRead($path)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $hash.Dispose() }
}
function ValidatePackage([string]$path, [string]$version) {
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        $firstManifest = $zip.Entries | Where-Object { [IO.Path]::GetFileName($_.FullName) -eq 'package.json' } | Select-Object -First 1
        if (-not $firstManifest -or $firstManifest.FullName -cne 'package.json' -or $firstManifest.Length -gt 65536) {
            throw 'Das Update hat kein gueltiges Collabsprite-Manifest an erster Stelle.'
        }
        $reader = [IO.StreamReader]::new($firstManifest.Open())
        try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        if ($manifest.name -cne 'pixelkollab-native' -or $manifest.version -cne $version -or
            @($manifest.contributes.scripts).Count -ne 1 -or $manifest.contributes.scripts[0].path -cne './main.lua') {
            throw 'Das Paket ist nicht die erwartete Collabsprite-Version.'
        }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        [long]$total = 0
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if ($name -match '\\|:|^/|(^|/)\.\.?(/|$)|[\x00-\x1f]' -or
                $name -match '(^|/)(data|__pref.lua|__info.json)(/|$)' -or -not $seen.Add($name)) {
                throw 'Unsicherer oder doppelter Dateipfad im Update.'
            }
            foreach ($component in $name.TrimEnd('/').Split('/')) {
                if (-not $component -or $component -match '[<>"|?*]|[. ]$|^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') {
                    throw 'Ungueltiger Windows-Dateiname im Update.'
                }
            }
            $total += $entry.Length
            if ($total -gt 268435456 -or $zip.Entries.Count -gt 4096) { throw 'Updatepaket zu gross.' }
        }
        if (-not $seen.Contains('main.lua')) { throw 'Collabsprite-Programmdatei fehlt im Update.' }
    } finally { $zip.Dispose() }
}
function PrepareInstallation {
    $inventoryPath = Join-Path $PSScriptRoot '__info.json'
    if (-not (Test-Path -LiteralPath $inventoryPath)) { return } # Source checkout, not an installed extension.
    Report 'PROGRESS preparing'
    $inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
    $root = [IO.Path]::GetFullPath($PSScriptRoot) + [IO.Path]::DirectorySeparatorChar
    $files = @('__info.json','package.json','__pref.lua') + @($inventory.installedFiles) | Select-Object -Unique
    $resolved = foreach ($name in $files) {
        $full = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $name))
        if (-not $full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or $name -match '(^|[\\/])data([\\/]|$)') {
            throw 'Ungueltige Installationsliste. Update sicher abgebrochen.'
        }
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            # Detect an active bundled host runtime before Aseprite removes anything.
            try { $probe = [IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $probe.Dispose() }
            catch { throw 'Collabsprite-Dateien werden noch verwendet. Andere Aseprite-Fenster und Host-Sitzungen bitte zuerst schliessen.' }
            [pscustomobject]@{ Name=$name; Path=$full }
        }
    }
    $backupRoot = Join-Path ([IO.Directory]::GetParent([IO.Directory]::GetParent($PSScriptRoot).FullName).FullName) 'Collabsprite-backups'
    $backup = Join-Path $backupRoot ('before-update-' + $InstalledVersion + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($file in $resolved) {
        $target = Join-Path $backup $file.Name
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
        Copy-Item -LiteralPath $file.Path -Destination $target
    }
}
try {
    Report 'PROGRESS checking'
    $headers = @{ 'User-Agent'='Collabsprite-Update'; 'Accept'='application/vnd.github+json' }
    $releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/Merthius/Collabsprite/releases?per_page=30' -Headers $headers -TimeoutSec 15 -UseBasicParsing
    $candidates = foreach ($release in $releases) {
        if ($release.draft -or $release.tag_name -notmatch '^v(\d+\.\d+\.\d+)$') { continue }
        $versionText = $Matches[1]
        $asset = @($release.assets | Where-Object { $_.name -eq 'Collabsprite.aseprite-extension' }) | Select-Object -First 1
        if (-not $asset -or $asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { continue }
        try { $version = [version]$versionText } catch { continue }
        [pscustomobject]@{ Tag=$release.tag_name; Version=$version; Digest=$asset.digest.Substring(7).ToLowerInvariant() }
    }
    $latest = $candidates | Sort-Object -Property Version -Descending | Select-Object -First 1
    if (-not $latest) { throw 'Kein gueltiger Collabsprite-Release mit SHA-256-Pruefsumme gefunden.' }
    $current = [version]($InstalledVersion -replace '-.*$','')
    if ($latest.Version -lt $current -or ($latest.Version -eq $current -and $InstalledVersion -notmatch '-')) {
        Report ('CURRENT ' + $InstalledVersion); exit 0
    }
    if (-not $DownloadDirectory) { $DownloadDirectory = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads' }
    New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null
    $stem = 'Collabsprite-' + $latest.Tag
    $destination = Join-Path $DownloadDirectory ($stem + '.aseprite-extension')
    if (Test-Path -LiteralPath $destination) {
        Report 'PROGRESS verifying'
        $existingHash = FileHash $destination
        if ($existingHash -eq $latest.Digest) {
            ValidatePackage $destination $latest.Version.ToString()
            PrepareInstallation
            Report ('DOWNLOADED ' + $latest.Tag + '|' + $destination); exit 0
        }
        $suffix = 2
        do {
            $destination = Join-Path $DownloadDirectory ($stem + '-' + $suffix + '.aseprite-extension')
            $suffix++
        } while (Test-Path -LiteralPath $destination)
    }
    $partial = Join-Path $DownloadDirectory ('.' + $stem + '-' + [guid]::NewGuid().ToString('N') + '.part')
    $url = 'https://github.com/Merthius/Collabsprite/releases/download/' + $latest.Tag + '/Collabsprite.aseprite-extension'
    Report 'PROGRESS downloading'
    Invoke-WebRequest -Uri $url -Headers @{ 'User-Agent'='Collabsprite-Update' } -TimeoutSec 120 -UseBasicParsing -OutFile $partial
    Report 'PROGRESS verifying'
    $downloadHash = FileHash $partial
    if ($downloadHash -ne $latest.Digest) { throw 'Die heruntergeladene Datei hat nicht die GitHub-Pruefsumme. Sie wurde verworfen.' }
    ValidatePackage $partial $latest.Version.ToString()
    [IO.File]::Move($partial,$destination)
    $partial = $null
    PrepareInstallation
    Report ('DOWNLOADED ' + $latest.Tag + '|' + $destination)
} catch {
    $message = $_.Exception.Message -replace '[\r\n]+',' '
    Report ('ERROR ' + $message)
    exit 1
} finally {
    if ($partial -and (Test-Path -LiteralPath $partial)) { Remove-Item -LiteralPath $partial -Force }
}
