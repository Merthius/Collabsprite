# PowerShell 7; every case gets fresh native Aseprite objects in batch mode.
param([string]$Aseprite = 'C:/Program Files (x86)/Steam/steamapps/common/Aseprite/aseprite.exe')
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Bitte mit PowerShell 7 (pwsh) ausführen.' }
if (-not (Test-Path -LiteralPath $Aseprite)) { throw 'Aseprite fehlt. Mit -Aseprite den Programmpfad angeben.' }
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$results=Join-Path $repo 'test-results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
$cases=@('plain','codec','structure','resume','safety','lifecycle','callbacks','controller','update-ui',
  'notes','notes-inline','notes-stack','notes-board','notes-animation','notes-paper','notes-paper-ui',
  'notes-inflight','notes-file-import','notes-responsive','ui-layout','diagnostics-ui')
foreach ($case in $cases) {
  $info=[Diagnostics.ProcessStartInfo]::new($Aseprite)
  $info.UseShellExecute=$false; $info.CreateNoWindow=$true
  $info.WorkingDirectory=$repo
  $info.Environment['ASEPRITE_USER_FOLDER']=Join-Path $results 'batch-profile'
  $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
  foreach ($arg in @('--batch','--script-param',('root='+$repo.Replace('\','/')),'--script',"test/$case.lua")) { $info.ArgumentList.Add($arg) }
  $process=[Diagnostics.Process]::Start($info)
  try {
    $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw "Zeitlimit im nativen Test: $case" }
    $output=$stdout.Result+$stderr.Result
    [IO.File]::WriteAllText((Join-Path $results ($case+'.log')),$output)
    if ($process.ExitCode -ne 0 -or $output -notmatch 'PASS') { throw "Test $case fehlgeschlagen: $output" }
    Write-Output "PASS $case"
  } finally { $process.Dispose() }
}
Write-Output ("PASS: alle "+$cases.Count+' nativen Prüfungen')
