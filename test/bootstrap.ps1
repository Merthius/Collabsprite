$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\output\Collabsprite.aseprite-extension'))
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempRoot ('Collabsprite-test-' + [guid]::NewGuid().ToString('N'))
$port = 18765
$resultPath = Join-Path $tempRoot ('Collabsprite-start-' + [guid]::NewGuid().ToString('N') + '.status')
$ownedPid = $null
if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) { throw 'Testport belegt.' }
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    [IO.Compression.ZipFile]::ExtractToDirectory($package,$testRoot)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $launcher = Join-Path $testRoot 'Launcher.vbs'
    $scriptHost = Start-Process -FilePath wscript.exe -ArgumentList @('//B','//Nologo',('"' + $launcher + '"'),'Host','Test',$port,('"' + $resultPath + '"'),'0') -WindowStyle Hidden -PassThru
    if (-not $scriptHost.WaitForExit(4000)) { throw 'Launcher beendet sich nicht rechtzeitig.' }
    $watch.Stop()
    if ($scriptHost.ExitCode -ne 0) { throw ('Launcher fehlgeschlagen: ' + $scriptHost.ExitCode) }
    if ($watch.Elapsed.TotalSeconds -gt 4) { throw ('Aseprite-Start wäre zu langsam: ' + $watch.Elapsed.TotalSeconds) }
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    $result = ''
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $resultPath) { $result = Get-Content -LiteralPath $resultPath -Raw }
        if ($result -and $result -ne 'QUEUED') { break }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $resultPath)) { throw 'Worker hat keinen Status geliefert.' }
    if ($result -notlike 'READY 18765*') { throw ('Worker meldet: ' + $result) }
    $status = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $port + '/status') -TimeoutSec 2
    if ($status.app -ne 'Collabsprite' -or $status.protocol -ne 2 -or -not $status.localOnly) { throw 'Falscher Serverstatus.' }
    $joinResult = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $testRoot 'Bootstrap.ps1') -Action Join -Mode Network -Port $port -Endpoints ('127.0.0.1:' + $port)
    if ($LASTEXITCODE -ne 0 -or $joinResult -ne ('READY 127.0.0.1:' + $port)) { throw ('Join-Adresse nicht erkannt: ' + $joinResult) }
    $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop | Select-Object -First 1
    $process = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $listener.OwningProcess)
    if ($process.Name -ne 'node.exe' -or $process.CommandLine -notlike ('*' + $testRoot + '*') -or $process.CommandLine -notlike '*--port=18765*') {
        throw 'Serverprozess gehört nicht zum Test.'
    }
    $ownedPid = $process.ProcessId
    Write-Output ('PASS: Launcher in ' + [Math]::Round($watch.Elapsed.TotalSeconds,2) + ' s zurück; Server später bereit.')
} finally {
    if ($ownedPid) { Stop-Process -Id $ownedPid -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $resultPath) { Remove-Item -LiteralPath $resultPath }
    if (-not $testRoot.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($testRoot) -notmatch '^Collabsprite-test-[a-f0-9]{32}$') { throw 'Unerwartetes Testverzeichnis.' }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
