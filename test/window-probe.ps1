$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TestBoardWindow {
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr window,uint command);
  [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr window,int index);
}
'@
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$token='f024b837e5a84f8cadb2ef1a93c0d654'
$main=New-Object Windows.Forms.Form
$board=New-Object Windows.Forms.Form
try {
  $main.Text='Probe - Aseprite v1.3'
  $main.StartPosition='Manual';$main.Location=New-Object Drawing.Point(-3000,-3000)
  $board.Text='Collabsprite - Ideenwand #'+$token.Substring(0,12)
  $board.FormBorderStyle='SizableToolWindow'
  $board.ShowInTaskbar=$false
  $board.StartPosition='Manual';$board.Location=New-Object Drawing.Point(-2750,-3000)
  $main.Show();$board.Show($main)
  [Windows.Forms.Application]::DoEvents()
  if([TestBoardWindow]::GetWindow($board.Handle,4) -ne $main.Handle) { throw 'Probe window has no owner' }
  & powershell.exe -NoProfile -NonInteractive -File (Join-Path $root 'extension\Window.ps1') -Token $token
  if($LASTEXITCODE -ne 0) { throw "Window promotion failed: $LASTEXITCODE" }
  [Windows.Forms.Application]::DoEvents()
  if([TestBoardWindow]::GetWindow($board.Handle,4) -ne [IntPtr]::Zero) { throw 'Board remains owned' }
  $style=[TestBoardWindow]::GetWindowLongPtr($board.Handle,-20).ToInt64()
  if(($style -band 0x80) -ne 0 -or ($style -band 0x40000) -eq 0) { throw 'Board has no normal taskbar style' }
  Write-Host 'PASS independent Windows board window'
} finally {
  $board.Close();$main.Close();$board.Dispose();$main.Dispose()
}
