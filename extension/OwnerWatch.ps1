# Hold a handle to the verified Aseprite, not a potentially reused PID.
# Never modifies, activates or terminates that process.
param([ValidateRange(1,2147483647)][int]$OwnerPid,
      [ValidatePattern('^[0-9]{18,19}$')][string]$OwnerStart)
$ErrorActionPreference='Stop'
try { $owner=Get-Process -Id $OwnerPid -ErrorAction Stop } catch { exit 0 }
try {
    if ($owner.ProcessName -ne 'aseprite' -or $owner.HasExited -or
        $owner.StartTime.ToUniversalTime().Ticks.ToString() -ne $OwnerStart) { exit 0 }
    $owner.WaitForExit()
} catch { exit 22 } finally { $owner.Dispose() }
exit 0
