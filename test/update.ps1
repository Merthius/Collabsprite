$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('Collabsprite-update-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $testAsset = Join-Path $testRoot 'fixture.aseprite-extension'
    [IO.File]::WriteAllText($testAsset,'harmless fixture for download verification')
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
    Write-Output 'PASS: stable/dev/dev.1 update paths, no downgrade, SHA-256 rejection and cleanup'
    $global:LASTEXITCODE = 0 # The corrupt-download case intentionally returned 1.
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^Collabsprite-update-test-[a-f0-9]{32}$') { throw 'Unexpected cleanup target' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
