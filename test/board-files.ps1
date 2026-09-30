$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Add-Type -Path (Join-Path $root 'extension/BoardFiles.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Web.Extensions
$image=Join-Path $root 'test-results\file-drop.png'
$bitmap=New-Object Drawing.Bitmap(16,16)
try {
  $bitmap.SetPixel(3,4,[Drawing.Color]::Blue);$bitmap.Save($image,[Drawing.Imaging.ImageFormat]::Png)
  $data=New-Object Windows.Forms.DataObject
  $data.SetData([Windows.Forms.DataFormats]::FileDrop,[string[]]@($image,$image))
  $event=[CollabspriteFiles]::FileDrop($data,[Drawing.Rectangle]::new(100,200,400,600),200,500)
  if($event.paths.Count -ne 2 -or $event.x -ne .25 -or $event.y -ne .5) { throw 'Native drop paths or coordinates are wrong' }
  if([CollabspriteFiles]::Supported('bad.aseprite') -or [CollabspriteFiles]::Supported('bad.exe')) { throw 'Non-image file allowed' }
  $rejected=$false
  try { [void][CollabspriteFiles]::Validate([string[]]@('C:\missing.png')) } catch { $rejected=$true }
  if(-not $rejected) { throw 'Missing file accepted' }
  $rejected=$false
  try { [void][CollabspriteFiles]::Validate([string[]](@($image)*33)) } catch { $rejected=$true }
  if(-not $rejected) { throw 'File count limit missing' }
  $token=[guid]::NewGuid().ToString('N')
  [CollabspriteFiles]::Write($token,$event)
  $mailbox=Join-Path ([IO.Path]::GetTempPath()) ('Collabsprite-files-'+$token+'.json')
  $roundtrip=Get-Content -LiteralPath $mailbox -Raw -Encoding UTF8 | ConvertFrom-Json
  if($roundtrip.paths.Count -ne 2 -or $roundtrip.status -ne 'ok' -or $roundtrip.x -ne .25) { throw 'Mailbox changed drop' }
  Remove-Item -LiteralPath $mailbox
  Write-Host 'PASS Windows image drop data, multi-file selection validation and atomic mailbox'
} finally { $bitmap.Dispose();if(Test-Path -LiteralPath $image) { Remove-Item -LiteralPath $image } }
