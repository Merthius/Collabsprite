$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('Collabsprite-update-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $testAsset = Join-Path $testRoot 'fixture.aseprite-extension'
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    function MakeFixture([string]$name='pixelkollab-native',[string]$version='0.6.5',[string]$extra='') {
        if (Test-Path -LiteralPath $testAsset) { Remove-Item -LiteralPath $testAsset }
        $zip = [IO.Compression.ZipFile]::Open($testAsset,[IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($path in @('package.json','main.lua') + @($extra | Where-Object { $_ })) {
                $entry = $zip.CreateEntry($path)
                $writer = [IO.StreamWriter]::new($entry.Open())
                try {
                    if ($path -eq 'package.json') { $writer.Write((@{name=$name;version=$version;contributes=@{scripts=@(@{path='./main.lua'})}} | ConvertTo-Json -Depth 5)) }
                    else { $writer.Write('-- harmless update test') }
                } finally { $writer.Dispose() }
            }
        } finally { $zip.Dispose() }
    }
    MakeFixture
    $testDigest = (Get-FileHash -LiteralPath $testAsset -Algorithm SHA256).Hash.ToLowerInvariant()
    function Invoke-RestMethod {
        return @([pscustomobject]@{draft=$false;tag_name='v0.6.5';assets=@([pscustomobject]@{
            name='Collabsprite.aseprite-extension';digest=('sha256:' + $testDigest)})})
    }
    function Invoke-WebRequest { param($OutFile) Copy-Item -LiteralPath $testAsset -Destination $OutFile }
    foreach ($version in @('0.6.4','0.6.5-dev','0.6.5-dev.1','0.6.5','0.6.6')) {
        $status = Join-Path $testRoot ($version + '.status')
        & (Join-Path $PSScriptRoot '..\extension\Update.ps1') -ResultPath $status -InstalledVersion $version -DownloadDirectory $testRoot
        $result = Get-Content -LiteralPath $status -Raw
        $expected = if ($version -in @('0.6.5','0.6.6')) { 'CURRENT ' } else { 'DOWNLOADED v0.6.5|' }
        if (-not $result.StartsWith($expected)) { throw ('Update failed for ' + $version + ': ' + $result) }
    }
    $testDigest = '0' * 64
    $status = Join-Path $testRoot 'mismatch.status'
    & (Join-Path $PSScriptRoot '..\extension\Update.ps1') -ResultPath $status -InstalledVersion '0.6.4' -DownloadDirectory $testRoot
    if ((Get-Content -LiteralPath $status -Raw) -notlike 'ERROR *Pruefsumme*') { throw 'Corrupt update accepted' }
    if (Get-ChildItem -LiteralPath $testRoot -Filter '*.part' -Force) { throw 'Partial update left behind' }
    foreach ($case in @(@('ws','0.6.5',''),@('pixelkollab-native','0.6.4',''),@('pixelkollab-native','0.6.5','../escape'),@('pixelkollab-native','0.6.5','data/room.json'),@('pixelkollab-native','0.6.5','AUX.txt'))) {
        MakeFixture $case[0] $case[1] $case[2]
        $testDigest = (Get-FileHash -LiteralPath $testAsset -Algorithm SHA256).Hash.ToLowerInvariant()
        & (Join-Path $PSScriptRoot '..\extension\Update.ps1') -ResultPath $status -InstalledVersion '0.6.4' -DownloadDirectory $testRoot
        if ((Get-Content -LiteralPath $status -Raw) -notlike 'ERROR *') { throw 'Invalid extension accepted' }
    }
    # Exercise the real installed-worker preflight/backup in a disposable profile.
    MakeFixture
    $testDigest = (Get-FileHash -LiteralPath $testAsset -Algorithm SHA256).Hash.ToLowerInvariant()
    $installed = Join-Path $testRoot 'Aseprite\extensions\pixelkollab-native'
    New-Item -ItemType Directory -Path $installed -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\extension\Update.ps1') -Destination $installed
    [IO.File]::WriteAllText((Join-Path $installed 'main.lua'),'old code')
    [IO.File]::WriteAllText((Join-Path $installed '__pref.lua'),'user settings')
    [IO.File]::WriteAllText((Join-Path $installed '__info.json'),'{"installedFiles":["main.lua","Update.ps1"]}')
    $lock = [IO.File]::Open((Join-Path $installed 'main.lua'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        & (Join-Path $installed 'Update.ps1') -ResultPath $status -InstalledVersion '0.6.4' -DownloadDirectory $testRoot
        if ((Get-Content -LiteralPath $status -Raw) -notlike 'ERROR *verwendet*') { throw 'Locked installation accepted' }
    } finally { $lock.Dispose() }
    & (Join-Path $installed 'Update.ps1') -ResultPath $status -InstalledVersion '0.6.4' -DownloadDirectory $testRoot
    if ((Get-Content -LiteralPath $status -Raw) -notlike 'DOWNLOADED *') { throw 'Prepared installation failed' }
    $backupPrefs = @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'Aseprite\Collabsprite-backups') -Filter '__pref.lua' -Recurse)
    if ($backupPrefs.Count -ne 1 -or [IO.File]::ReadAllText($backupPrefs[0].FullName) -ne 'user settings') { throw 'Backup missing settings' }
    if ([IO.File]::ReadAllText((Join-Path $installed 'main.lua')) -ne 'old code') { throw 'Worker overwrote live extension' }
    Write-Output 'PASS: versions, digest, package identity/paths, locked files, backup, live files untouched'
    $global:LASTEXITCODE = 0 # The corrupt-download case intentionally returned 1.
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^Collabsprite-update-test-[a-f0-9]{32}$') { throw 'Unexpected cleanup target' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
