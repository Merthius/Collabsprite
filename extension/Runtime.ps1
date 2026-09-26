# Shared by the unprivileged starter and the elevated firewall helper.
function Get-CollabspriteNode {
    $bundled = Join-Path $PSScriptRoot 'runtime\node.exe'
    if (Test-Path -LiteralPath $bundled) { return [IO.Path]::GetFullPath($bundled) }
    # Source checkout fallback; release packages always contain the runtime.
    $command = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw 'Host-Laufzeit fehlt. Die aktuelle Collabsprite.aseprite-extension neu installieren.'
}
