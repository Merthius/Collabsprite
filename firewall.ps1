param([string]$NodePath = '')
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Bitte die einmalige Collabsprite-Firewallfreigabe als Administrator bestaetigen.'
}
if (-not $NodePath) {
    $resolver = Join-Path $PSScriptRoot 'Runtime.ps1'
    if (-not (Test-Path -LiteralPath $resolver)) { $resolver = Join-Path $PSScriptRoot 'extension\Runtime.ps1' }
    . $resolver
    $NodePath = Get-CollabspriteNode
}
$NodePath = (Resolve-Path -LiteralPath $NodePath).Path
if ([IO.Path]::GetFileName($NodePath) -ne 'node.exe') { throw 'Ungueltige Host-Laufzeit.' }
$ruleName = 'Collabsprite-Radmin-TCP-8766'
$existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
if ($existing) {
    Set-NetFirewallRule -Name $ruleName -Program $NodePath -Enabled True -Action Allow -Direction Inbound -Protocol TCP -LocalPort 8766 -RemoteAddress '26.0.0.0/8' -Profile Any | Out-Null
} else {
    New-NetFirewallRule -Name $ruleName -DisplayName 'Collabsprite - Radmin TCP 8766' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8766 -RemoteAddress '26.0.0.0/8' -Program $nodePath -Profile Any | Out-Null
    Write-Host 'TCP 8766 fuer Node.js und ausschliesslich Radmin-Adressen freigegeben.'
}
Write-Host "Rueckgaengig: Remove-NetFirewallRule -Name '$ruleName'"
$discoveryRule = 'Collabsprite-Radmin-UDP-8766'
if (-not (Get-NetFirewallRule -Name $discoveryRule -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $discoveryRule -DisplayName 'Collabsprite - Radmin Sitzungssuche UDP 8766' -Direction Inbound -Action Allow -Protocol UDP -LocalPort 8766 -RemoteAddress '26.0.0.0/8' -Program $nodePath -Profile Any | Out-Null
    Write-Host 'UDP 8766 fuer Sitzungssuche ausschliesslich ueber Radmin freigegeben.'
} else {
    Set-NetFirewallRule -Name $discoveryRule -Program $NodePath -Enabled True -Action Allow -Direction Inbound -Protocol UDP -LocalPort 8766 -RemoteAddress '26.0.0.0/8' -Profile Any | Out-Null
}
Write-Host "Rueckgaengig: Remove-NetFirewallRule -Name '$discoveryRule'"
foreach ($protocol in @('TCP','UDP')) {
    $lanRule = 'Collabsprite-LAN-' + $protocol + '-8766'
    if (-not (Get-NetFirewallRule -Name $lanRule -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name $lanRule -DisplayName ('Collabsprite - LAN ' + $protocol + ' 8766') -Direction Inbound -Action Allow -Protocol $protocol -LocalPort 8766 -RemoteAddress LocalSubnet -Program $nodePath -Profile Private,Domain | Out-Null
        Write-Host ($protocol + ' 8766 nur fuer lokales Subnetz auf privaten/Domain-Netzen freigegeben.')
    } else {
        Set-NetFirewallRule -Name $lanRule -Program $NodePath -Enabled True -Action Allow -Direction Inbound -Protocol $protocol -LocalPort 8766 -RemoteAddress LocalSubnet -Profile Private,Domain | Out-Null
    }
    Write-Host "Rueckgaengig: Remove-NetFirewallRule -Name '$lanRule'"
}
