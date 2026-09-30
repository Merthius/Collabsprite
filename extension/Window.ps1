param([Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{32}$')][string]$Token)
$ErrorActionPreference='Stop'
$title="Collabsprite - Ideenwand #$($Token.Substring(0,12))"

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class CollabspriteBoardWindow {
  public delegate bool WindowCallback(IntPtr window, IntPtr context);
  [DllImport("user32.dll")] public static extern bool EnumWindows(WindowCallback callback, IntPtr context);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr window,StringBuilder text,int capacity);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window,out uint processId);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr window,uint command);
  [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW",SetLastError=true)] public static extern IntPtr GetWindowLongPtr(IntPtr window,int index);
  [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW",SetLastError=true)] public static extern IntPtr SetWindowLongPtr(IntPtr window,int index,IntPtr value);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window,IntPtr behind,int x,int y,int width,int height,uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window,int command);
}
'@

function Find-Board {
  $found=[Collections.Generic.List[object]]::new()
  [void][CollabspriteBoardWindow]::EnumWindows({
    param($handle,$context)
    if(-not [CollabspriteBoardWindow]::IsWindowVisible($handle)) { return $true }
    $name=[Text.StringBuilder]::new(256)
    [void][CollabspriteBoardWindow]::GetWindowText($handle,$name,$name.Capacity)
    if($name.ToString() -cne $title) { return $true }
    $processId=[uint32]0
    [void][CollabspriteBoardWindow]::GetWindowThreadProcessId($handle,[ref]$processId)
    $owner=[CollabspriteBoardWindow]::GetWindow($handle,4)
    if($owner -eq [IntPtr]::Zero) { return $true }
    $ownerPid=[uint32]0
    [void][CollabspriteBoardWindow]::GetWindowThreadProcessId($owner,[ref]$ownerPid)
    if($processId -ne $ownerPid) { return $true }
    $ownerTitle=[Text.StringBuilder]::new(256)
    [void][CollabspriteBoardWindow]::GetWindowText($owner,$ownerTitle,$ownerTitle.Capacity)
    if($ownerTitle.ToString() -notmatch 'Aseprite v[0-9]') { return $true }
    $found.Add($handle)
    return $true
  },[IntPtr]::Zero)
  if($found.Count -ne 1) { return [IntPtr]::Zero }
  return $found[0]
}

$board=[IntPtr]::Zero
for($attempt=0;$attempt -lt 20 -and $board -eq [IntPtr]::Zero;$attempt++) {
  $board=Find-Board
  if($board -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 75 }
}
if($board -eq [IntPtr]::Zero) { exit 1 }

# Aseprite creates an owned tool window. That style keeps it out of Windows'
# normal task list and Snap Assist suggestions. Never resize the editor here.
$style=[CollabspriteBoardWindow]::GetWindowLongPtr($board,-20).ToInt64()
$newStyle=($style -band (-bnot [long]0x80)) -bor [long]0x40000
[void][CollabspriteBoardWindow]::SetWindowLongPtr($board,-8,[IntPtr]::Zero)
if([CollabspriteBoardWindow]::GetWindow($board,4) -ne [IntPtr]::Zero) { exit 2 }
[void][CollabspriteBoardWindow]::SetWindowLongPtr($board,-20,[IntPtr]::new($newStyle))
if(([CollabspriteBoardWindow]::GetWindowLongPtr($board,-20).ToInt64() -band [long]0x40080) -ne [long]0x40000) { exit 3 }
[void][CollabspriteBoardWindow]::SetWindowPos($board,[IntPtr]::Zero,0,0,0,0,0x27)
[void][CollabspriteBoardWindow]::ShowWindow($board,0)
[void][CollabspriteBoardWindow]::ShowWindow($board,5)
