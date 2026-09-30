param(
  [ValidateSet('Pick','Drop')][string]$Mode,
  [ValidatePattern('^[a-f0-9]{32}$')][string]$Token,
  [ValidatePattern('^[a-f0-9]{32}$')][string]$Board
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions
Add-Type -Path (Join-Path $PSScriptRoot 'BoardFiles.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Web.Extensions
[CollabspriteFiles]::Run($Mode,$Token,$Board)
