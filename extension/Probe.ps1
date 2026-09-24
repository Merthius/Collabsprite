# One-shot discovery across this PC, the local subnet and an active Radmin VPN.
param([ValidateRange(1,65535)][int]$Port = 8766)
$ErrorActionPreference = 'Stop'
$entries = @([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
    Where-Object { $_.OperationalStatus -eq 'Up' } |
    ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
    Where-Object { $_.Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork })
function IsPrivate([byte[]]$bytes) {
    return $bytes[0] -eq 10 -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168)
}
function IsAllowed([Net.IPAddress]$address) {
    if ([Net.IPAddress]::IsLoopback($address)) { return $true }
    $bytes = $address.GetAddressBytes()
    foreach ($entry in $entries) {
        $own = $entry.Address.GetAddressBytes()
        if ($own[0] -eq 26 -and $bytes[0] -eq 26) { return $true }
        if (-not (IsPrivate $own) -or -not (IsPrivate $bytes)) { continue }
        $mask = $entry.IPv4Mask.GetAddressBytes()
        $same = $true
        for ($i=0; $i -lt 4; $i++) { if (($own[$i] -band $mask[$i]) -ne ($bytes[$i] -band $mask[$i])) { $same=$false; break } }
        if ($same) { return $true }
    }
    return $false
}
$probeClient = [Net.Sockets.UdpClient]::new(0)
try {
    $probeClient.EnableBroadcast = $true
    $requestBytes = [Text.Encoding]::ASCII.GetBytes('COLLABSPRITE_DISCOVER_V2')
    $addresses = @('127.0.0.1')
    foreach ($entry in $entries) {
        $own = $entry.Address.GetAddressBytes()
        if ($own[0] -eq 26) {
            $addresses += '26.255.255.255'
            $addresses += $entry.Address.ToString()
        } elseif (IsPrivate $own) {
            $mask = $entry.IPv4Mask.GetAddressBytes()
            $broadcast = for ($i=0; $i -lt 4; $i++) { [byte]($own[$i] -bor (255 -bxor $mask[$i])) }
            $addresses += ($broadcast -join '.')
        }
    }
    foreach ($address in ($addresses | Select-Object -Unique)) {
        try { [void]$probeClient.Send($requestBytes,$requestBytes.Length,$address,$Port) }
        catch [Net.Sockets.SocketException] { } # An inactive adapter is normal.
    }
    $deadline = [DateTime]::UtcNow.AddMilliseconds(1500)
    while ([DateTime]::UtcNow -lt $deadline) {
        $probeClient.Client.ReceiveTimeout = [Math]::Max(1,[int]($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        try {
            $sender = [Net.IPEndPoint]::new([Net.IPAddress]::Any,0)
            $reply = $probeClient.Receive([ref]$sender)
            if ($reply.Length -le 2000 -and (IsAllowed $sender.Address)) {
                $line = [Text.Encoding]::UTF8.GetString($reply)
                if ($line.StartsWith('{"protocol":2,"rooms":',[StringComparison]::Ordinal)) { [Console]::WriteLine($line) }
            }
        } catch [Net.Sockets.SocketException] {
            if ([DateTime]::UtcNow -ge $deadline) { break }
        }
    }
} finally { $probeClient.Close() }
