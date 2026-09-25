# Detached update worker. Aseprite polls ResultPath instead of waiting for HTTPS.
param(
    [Parameter(Mandatory=$true)][string]$ResultPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(-dev)?$')][string]$InstalledVersion,
    [string]$DownloadDirectory = ''
)
$ErrorActionPreference = 'Stop'
$partial = $null
function Report([string]$line) {
    $temporary = $ResultPath + '.tmp'
    [IO.File]::WriteAllText($temporary,$line,[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $ResultPath -Force
}
try {
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
    $current = [version]($InstalledVersion -replace '-dev$','')
    if ($latest.Version -lt $current -or ($latest.Version -eq $current -and $InstalledVersion -notlike '*-dev')) {
        Report ('CURRENT ' + $InstalledVersion); exit 0
    }
    if (-not $DownloadDirectory) { $DownloadDirectory = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads' }
    New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null
    $stem = 'Collabsprite-' + $latest.Tag
    $destination = Join-Path $DownloadDirectory ($stem + '.aseprite-extension')
    if (Test-Path -LiteralPath $destination) {
        $existingHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($existingHash -eq $latest.Digest) { Report ('DOWNLOADED ' + $latest.Tag + '|' + $destination); exit 0 }
        $suffix = 2
        do {
            $destination = Join-Path $DownloadDirectory ($stem + '-' + $suffix + '.aseprite-extension')
            $suffix++
        } while (Test-Path -LiteralPath $destination)
    }
    $partial = Join-Path $DownloadDirectory ('.' + $stem + '-' + [guid]::NewGuid().ToString('N') + '.part')
    $url = 'https://github.com/Merthius/Collabsprite/releases/download/' + $latest.Tag + '/Collabsprite.aseprite-extension'
    Invoke-WebRequest -Uri $url -Headers @{ 'User-Agent'='Collabsprite-Update' } -TimeoutSec 20 -UseBasicParsing -OutFile $partial
    $downloadHash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($downloadHash -ne $latest.Digest) { throw 'Die heruntergeladene Datei hat nicht die GitHub-Pruefsumme. Sie wurde verworfen.' }
    [IO.File]::Move($partial,$destination)
    $partial = $null
    Report ('DOWNLOADED ' + $latest.Tag + '|' + $destination)
} catch {
    $message = $_.Exception.Message -replace '[\r\n]+',' '
    Report ('ERROR ' + $message)
    exit 1
} finally {
    if ($partial -and (Test-Path -LiteralPath $partial)) { Remove-Item -LiteralPath $partial -Force }
}
