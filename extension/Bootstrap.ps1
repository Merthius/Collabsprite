# Started by the Aseprite dialog. Only the host starts Node; guests need no server.
param([ValidateSet('Host','Join','Search')][string]$Action,
      [ValidateSet('Network','Test')][string]$Mode,
      [ValidateRange(1,65535)][int]$Port = 8766,
      [string]$ResultPath = '',
      [string]$Endpoints = '0',
      [ValidateRange(0,2147483647)][int]$OwnerPid = 0,
      [ValidatePattern('^$|^[a-f0-9]{32}$')][string]$OwnerToken = '')
$ErrorActionPreference = 'Stop'
function Report([string]$line) {
    if ($ResultPath) {
        $temporary = $ResultPath + '.tmp'
        [IO.File]::WriteAllText($temporary,$line,[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $ResultPath -Force
    } else { [Console]::WriteLine($line) }
}
function Fail([string]$message) { Report ('ERROR ' + $message); exit 1 }
function Check-Cancel {
    if ($ResultPath -and (Test-Path -LiteralPath ($ResultPath+'.cancel'))) { Fail 'Vorbereitung abgebrochen.' }
}
function Find-Owner([string]$token) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class CollabspriteSessionWindow {
  public delegate bool Callback(IntPtr h,IntPtr state);
  [DllImport("user32.dll")] public static extern bool EnumWindows(Callback fn,IntPtr state);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder text,int length);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
}
'@
    $title='Collabsprite #'+$token.Substring(0,12)
    $matches=[Collections.Generic.List[int]]::new()
    [void][CollabspriteSessionWindow]::EnumWindows({
        param($handle,$state)
        $text=[Text.StringBuilder]::new(256)
        [void][CollabspriteSessionWindow]::GetWindowText($handle,$text,$text.Capacity)
        if ($text.ToString() -cne $title) { return $true }
        $ownerProcess=[uint32]0
        [void][CollabspriteSessionWindow]::GetWindowThreadProcessId($handle,[ref]$ownerProcess)
        $owner=Get-Process -Id $ownerProcess -ErrorAction SilentlyContinue
        if ($owner -and $owner.ProcessName -eq 'aseprite') { $matches.Add([int]$ownerProcess) }
        return $true
    },[IntPtr]::Zero)
    if ($matches.Count -ne 1) { Fail 'Das Multiplayer-Fenster wurde geschlossen. Bitte erneut erstellen.' }
    return $matches[0]
}
function ServerStatus {
    try { return Invoke-RestMethod -Uri ('http://127.0.0.1:' + $Port + '/status') -TimeoutSec 1 -UseBasicParsing }
    catch { return $null }
}
try {
    Check-Cancel
    if ($Action -eq 'Search') {
        $probe = Join-Path $PSScriptRoot 'Probe.ps1'
        if (-not (Test-Path -LiteralPath $probe)) { Fail 'Sitzungssuche fehlt. Collabsprite neu installieren.' }
        $found = @(& $probe -Port $Port)
        Report ("SEARCH`n" + ($found -join "`n")); exit 0
    }
    if ($Action -eq 'Join') {
        if ($Endpoints -eq '0') { Report ('READY ' + $Port); exit 0 }
        if ($Endpoints.Length -gt 160 -or $Endpoints -notmatch '^[0-9.,:]+$') { Fail 'Einladungscode enthält ungültige Adressen.' }
        foreach ($candidate in ($Endpoints -split ',' | Select-Object -First 8)) {
            if ($candidate -notmatch '^((?:\d{1,3}\.){3}\d{1,3}):(\d{1,5})$') { continue }
            $ip = $Matches[1]; $candidatePort = [int]$Matches[2]
            if ($candidatePort -lt 1 -or $candidatePort -gt 65535) { continue }
            $parsed = [Net.IPAddress]::Parse($ip)
            $bytes = $parsed.GetAddressBytes()
            $private = $ip -eq '127.0.0.1' -or $bytes[0] -eq 10 -or
                ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
                ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or $bytes[0] -eq 26
            if (-not $private) { continue }
            try {
                $status = Invoke-RestMethod -Uri ('http://' + $candidate + '/status') -TimeoutSec 1 -UseBasicParsing
                if ($status.app -eq 'Collabsprite' -and $status.protocol -eq 14 -and $status.port -eq $candidatePort) {
                    Report ('READY ' + $candidate); exit 0
                }
            } catch { }
        }
        Fail 'Host nicht erreichbar. Beide PCs im selben LAN oder Radmin-Netz? Windows-Firewall prüfen.'
    }
    . (Join-Path $PSScriptRoot 'Runtime.ps1')
    if ($OwnerToken) { $OwnerPid=Find-Owner $OwnerToken }
    $node = Get-CollabspriteNode
    $serverFile = Join-Path $PSScriptRoot 'server.mjs'
    if (-not (Test-Path -LiteralPath $serverFile)) { Fail 'Serverdateien fehlen. Collabsprite neu installieren.' }
    $status = ServerStatus
    if ($status) {
        if ($status.app -ne 'Collabsprite' -or $status.protocol -ne 14 -or [bool]$status.localOnly -ne ($Mode -eq 'Test')) {
            Fail ('Port ' + $Port + ' ist durch einen anderen Server belegt.')
        }
        Report ('READY ' + $Port); exit 0
    }
    if ($Mode -eq 'Network') {
        Check-Cancel
        $rules = @('Collabsprite-LAN-TCP-8766','Collabsprite-LAN-UDP-8766','Collabsprite-Radmin-TCP-8766','Collabsprite-Radmin-UDP-8766')
        $needsFirewall = @($rules | Where-Object {
            $rule = Get-NetFirewallRule -Name $_ -ErrorAction SilentlyContinue
            if (-not $rule) { return $true }
            $program = ($rule | Get-NetFirewallApplicationFilter).Program
            return ($program -ne $node -or $rule.Enabled -ne 'True' -or $rule.Action -ne 'Allow')
        }).Count -gt 0
        if ($needsFirewall) {
            $firewallScript = Join-Path $PSScriptRoot 'firewall.ps1'
            $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"' + $firewallScript + '"'),'-NodePath',('"' + $node + '"'))
            $setup = Start-Process -FilePath powershell.exe -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
            if ($setup.ExitCode -ne 0) { Fail 'Die einmalige Windows-Firewallfreigabe wurde nicht erteilt.' }
        }
    }
    $serverMode = if ($Mode -eq 'Test') { '--local' } else { '--network' }
    Check-Cancel
    $arguments = @(('"' + $serverFile + '"'), $serverMode, ('--port=' + $Port), '--managed')
    if ($OwnerPid) {
        $owner = Get-Process -Id $OwnerPid -ErrorAction Stop
        try {
            if ($owner.ProcessName -ne 'aseprite' -or $owner.HasExited) { Fail 'Host-Aseprite wurde bereits geschlossen.' }
            $arguments += @(('--owner-pid='+$OwnerPid), ('--owner-start='+$owner.StartTime.ToUniversalTime().Ticks))
        } finally { $owner.Dispose() }
    }
    $serverProcess = Start-Process -FilePath $node -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $status = ServerStatus
        if ($status -and $status.app -eq 'Collabsprite' -and $status.protocol -eq 14 -and [bool]$status.localOnly -eq ($Mode -eq 'Test')) {
            Report ('READY ' + $Port); exit 0
        }
        if ($serverProcess.HasExited) { break }
    }
    if (-not $serverProcess.HasExited) { Stop-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue }
    Fail 'Server konnte nicht gestartet werden. Port oder Sicherheitssoftware prüfen.'
} catch { Fail $_.Exception.Message }
