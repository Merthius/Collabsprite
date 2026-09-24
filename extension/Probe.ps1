# One-shot session search. Uses Windows PowerShell and .NET already present on Windows.
param([ValidateRange(1,65535)][int]$Port = 8765,
      [ValidateSet('Local','Global')][string]$Mode = 'Local')
$ErrorActionPreference = 'Stop'
$probeClient = [Net.Sockets.UdpClient]::new(0)
try {
    $probeClient.EnableBroadcast = $true
    $requestBytes = [Text.Encoding]::ASCII.GetBytes('COLLABSPRITE_DISCOVER_V1')
    $addresses = @('127.0.0.1')
    if ($Mode -eq 'Global') {
        $addresses += '26.255.255.255'
        $addresses += @([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
            Where-Object { $_.Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and $_.Address.ToString().StartsWith('26.') } |
            ForEach-Object { $_.Address.ToString() })
    }
    foreach ($address in ($addresses | Select-Object -Unique)) {
        try { [void]$probeClient.Send($requestBytes,$requestBytes.Length,$address,$Port) }
        catch [Net.Sockets.SocketException] { } # Radmin may be offline.
    }
    $deadline = [DateTime]::UtcNow.AddMilliseconds(1500)
    while ([DateTime]::UtcNow -lt $deadline) {
        $probeClient.Client.ReceiveTimeout = [Math]::Max(1,[int]($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        try {
            $sender = [Net.IPEndPoint]::new([Net.IPAddress]::Any,0)
            $reply = $probeClient.Receive([ref]$sender)
            $fromLocal = [Net.IPAddress]::IsLoopback($sender.Address)
            $fromRadmin = $sender.Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and $sender.Address.GetAddressBytes()[0] -eq 26
            if ($reply.Length -le 2000 -and ($fromLocal -or $fromRadmin)) {
                $line = [Text.Encoding]::UTF8.GetString($reply)
                if ($line.StartsWith('{"protocol":1,"rooms":',[StringComparison]::Ordinal)) { [Console]::WriteLine($line) }
            }
        } catch [Net.Sockets.SocketException] {
            if ([DateTime]::UtcNow -ge $deadline) { break }
        }
    }
} finally { $probeClient.Close() }
