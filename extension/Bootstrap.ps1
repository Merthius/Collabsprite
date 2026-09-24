# Started by the Aseprite dialog. Only the host starts Node; guests need no server.
param([ValidateSet('Host','Join')][string]$Action,
      [ValidateSet('Local','Global')][string]$Mode,
      [ValidateRange(1,65535)][int]$Port = 8765,
      [string]$ResultPath = '')
$ErrorActionPreference = 'Stop'
function Report([string]$line) {
    if ($ResultPath) {
        $temporary = $ResultPath + '.tmp'
        [IO.File]::WriteAllText($temporary,$line,[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $ResultPath -Force
    } else { [Console]::WriteLine($line) }
}
function Fail([string]$message) { Report ('ERROR ' + $message); exit 1 }
function ServerStatus {
    try { return Invoke-RestMethod -Uri ('http://127.0.0.1:' + $Port + '/status') -TimeoutSec 1 -UseBasicParsing }
    catch { return $null }
}
try {
    if ($Mode -eq 'Global') {
        $radmin = 'C:\Program Files (x86)\Radmin VPN\RvRvpnGui.exe'
        if (-not (Test-Path -LiteralPath $radmin)) { Fail 'Radmin VPN ist nicht installiert.' }
        if (-not (Get-Process -Name 'RvRvpnGui' -ErrorAction SilentlyContinue)) {
            # Radmin is an interactive app: leave its GUI visible so the user can join a VPN network.
            $gui = [Diagnostics.ProcessStartInfo]::new($radmin)
            $gui.UseShellExecute = $true
            $gui.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal
            [Diagnostics.Process]::Start($gui) | Out-Null
            Report 'RADMIN_OPENED Radmin wurde geöffnet. Bitte dem gemeinsamen VPN-Netz beitreten und erneut versuchen.'
            exit 0
        }
        $address = @([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
            Where-Object { $_.Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and $_.Address.ToString().StartsWith('26.') })
        if ($address.Count -eq 0) { Fail 'Radmin ist geöffnet. Bitte einem gemeinsamen VPN-Netz beitreten und erneut versuchen.' }
    }
    if ($Action -eq 'Join') { Report ('READY ' + $Port); exit 0 }
    $node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
    if (-not $node) { Fail 'Node.js fehlt auf dem Host-PC (nodejs.org).' }
    $serverFile = Join-Path $PSScriptRoot 'server.mjs'
    if (-not (Test-Path -LiteralPath $serverFile)) { Fail 'Serverdateien fehlen. Collabsprite neu installieren.' }
    $status = ServerStatus
    if ($status) {
        if ($status.app -ne 'Collabsprite' -or [bool]$status.localOnly -ne ($Mode -eq 'Local')) {
            Fail ('Port ' + $Port + ' ist durch einen anderen Server belegt.')
        }
        Report ('READY ' + $Port); exit 0
    }
    if ($Mode -eq 'Global') {
        $tcpRule = Get-NetFirewallRule -Name 'Collabsprite-Radmin-TCP-8766' -ErrorAction SilentlyContinue
        $udpRule = Get-NetFirewallRule -Name 'Collabsprite-Radmin-UDP-8766' -ErrorAction SilentlyContinue
        if (-not $tcpRule -or -not $udpRule) {
            $firewallScript = Join-Path $PSScriptRoot 'firewall.ps1'
            $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"' + $firewallScript + '"'))
            $setup = Start-Process -FilePath powershell.exe -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
            if ($setup.ExitCode -ne 0) { Fail 'Die einmalige Windows-Firewallfreigabe wurde nicht erteilt.' }
        }
    }
    $arguments = @(('"' + $serverFile + '"'), ('--' + $Mode.ToLowerInvariant()), ('--port=' + $Port), '--managed')
    $serverProcess = Start-Process -FilePath $node -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $status = ServerStatus
        if ($status -and $status.app -eq 'Collabsprite' -and [bool]$status.localOnly -eq ($Mode -eq 'Local')) {
            Report ('READY ' + $Port); exit 0
        }
        if ($serverProcess.HasExited) { break }
    }
    if (-not $serverProcess.HasExited) { Stop-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue }
    Fail 'Server konnte nicht gestartet werden. Port oder Sicherheitssoftware prüfen.'
} catch { Fail $_.Exception.Message }
