$ErrorActionPreference = 'Stop'
$outputRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\output'))
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$stage = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('Collabsprite-build-' + [guid]::NewGuid().ToString('N'))))
$pluginBundle = Join-Path $stage 'plugin'
try {
New-Item -ItemType Directory -Force -Path $pluginBundle,(Join-Path $pluginBundle 'node_modules') | Out-Null
$pluginFiles = @('client.lua','codec.lua','diagnostics.lua','json.lua','main.lua','package.json','Probe.ps1','Bootstrap.ps1','Update.ps1','Launcher.vbs','LICENSE')
foreach ($name in $pluginFiles) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('extension\'+$name)) -Destination (Join-Path $pluginBundle $name) -Force }
foreach ($name in @('server.mjs','core.mjs','network.mjs','firewall.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $pluginBundle $name) -Force }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'node_modules\ws') -Destination (Join-Path $pluginBundle 'node_modules') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'extension\Runtime.ps1') -Destination $pluginBundle
# One installer for hosts and guests. Pin official, unmodified Node binaries.
# Downloads happen only at build time, never at the user's first host start.
$runtimeSpec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime.json') -Raw | ConvertFrom-Json
$cache = Join-Path $PSScriptRoot ('.cache\node-' + $runtimeSpec.version)
New-Item -ItemType Directory -Force -Path $cache,(Join-Path $pluginBundle 'runtime') | Out-Null
foreach ($asset in $runtimeSpec.assets) {
    $cached = Join-Path $cache $asset.name
    if (-not (Test-Path -LiteralPath $cached) -or (Get-FileHash -LiteralPath $cached -Algorithm SHA256).Hash -ne $asset.sha256) {
        Invoke-WebRequest -Uri $asset.url -UseBasicParsing -OutFile $cached -TimeoutSec 180
    }
    if ((Get-FileHash -LiteralPath $cached -Algorithm SHA256).Hash -ne $asset.sha256) { throw ('Runtime-Pruefsumme falsch: ' + $asset.name) }
    Copy-Item -LiteralPath $cached -Destination (Join-Path $pluginBundle ('runtime\' + $asset.name))
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'runtime.json') -Destination (Join-Path $pluginBundle 'runtime\runtime.json')
$extensionZip = Join-Path $stage 'Collabsprite-extension-build.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($extensionZip, [IO.Compression.ZipArchiveMode]::Create)
try {
    # Aseprite uses the FIRST package.json, even in a subdirectory.
    # Compress-Archive puts node_modules/ws/package.json first and installs ws!
    $manifestPath = Join-Path $pluginBundle 'package.json'
    $ordered = @((Get-Item -LiteralPath $manifestPath))
    $ordered += Get-ChildItem -LiteralPath $pluginBundle -File -Recurse | Where-Object { $_.FullName -ne $manifestPath } | Sort-Object FullName
    foreach ($file in $ordered) {
        $entry = $file.FullName.Substring($pluginBundle.Length + 1).Replace('\','/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$entry,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }
$extensionPackage = Join-Path $outputRoot 'Collabsprite.aseprite-extension'
Move-Item -LiteralPath $extensionZip -Destination $extensionPackage -Force
Write-Host "Erweiterung: $extensionPackage"
} finally {
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $stage.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([IO.Path]::GetFileName($stage)).StartsWith('Collabsprite-build-')) {
        throw "Unerwarteter Build-Pfad; nicht geloescht: $stage"
    }
    Remove-Item -LiteralPath $stage -Recurse -Force
}
