Option Explicit

Dim fso, shell, arguments, action, mode, port, resultPath, tempRoot, worker, command
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
Set arguments = WScript.Arguments

If arguments.Count <> 4 Then WScript.Quit 2
action = arguments(0)
mode = arguments(1)
port = arguments(2)
resultPath = fso.GetAbsolutePathName(arguments(3))
tempRoot = fso.GetAbsolutePathName(shell.ExpandEnvironmentStrings("%TEMP%")) & "\"

If action <> "Host" And action <> "Join" Then WScript.Quit 2
If mode <> "Local" And mode <> "Global" Then WScript.Quit 2
If Not IsNumeric(port) Then WScript.Quit 2
If CLng(port) < 1 Or CLng(port) > 65535 Then WScript.Quit 2
If LCase(Left(resultPath, Len(tempRoot))) <> LCase(tempRoot) Then WScript.Quit 2
If Left(fso.GetFileName(resultPath), 19) <> "Collabsprite-start-" Then WScript.Quit 2
If LCase(Right(resultPath, 7)) <> ".status" Then WScript.Quit 2

worker = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Bootstrap.ps1")
If Not fso.FileExists(worker) Then
  Report "ERROR Startskript fehlt."
  WScript.Quit 1
End If

Report "QUEUED"
command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Quote(worker) & _
  " -Action " & action & " -Mode " & mode & " -Port " & port & " -ResultPath " & Quote(resultPath)
On Error Resume Next
shell.Run command, 0, False
If Err.Number <> 0 Then
  Report "ERROR Hintergrundstart fehlgeschlagen: " & Err.Description
  WScript.Quit 1
End If
On Error GoTo 0

Function Quote(value)
  Quote = Chr(34) & Replace(value, Chr(34), "") & Chr(34)
End Function

Sub Report(message)
  Dim output
  Set output = fso.CreateTextFile(resultPath, True, False)
  output.Write message
  output.Close
End Sub
