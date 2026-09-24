$ErrorActionPreference = 'Stop'
$outputRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\output'))
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$stage = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('Collabsprite-build-' + [guid]::NewGuid().ToString('N'))))
$pluginBundle = Join-Path $stage 'plugin'
try {
New-Item -ItemType Directory -Force -Path $pluginBundle,(Join-Path $pluginBundle 'node_modules') | Out-Null
$pluginFiles = @('client.lua','codec.lua','main.lua','package.json','Probe.ps1','Bootstrap.ps1','Launcher.vbs','LICENSE')
foreach ($name in $pluginFiles) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('extension\'+$name)) -Destination (Join-Path $pluginBundle $name) -Force }
foreach ($name in @('server.mjs','core.mjs','network.mjs','firewall.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $pluginBundle $name) -Force }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'node_modules\ws') -Destination (Join-Path $pluginBundle 'node_modules') -Recurse -Force
$extensionZip = Join-Path $outputRoot 'Collabsprite-extension-build.zip'
Compress-Archive -Path (Join-Path $pluginBundle '*') -DestinationPath $extensionZip -Force
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
