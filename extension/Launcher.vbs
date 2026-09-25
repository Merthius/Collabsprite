Option Explicit

Dim fso, shell, arguments, action, mode, port, resultPath, endpoints, worker, command
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
Set arguments = WScript.Arguments

If arguments.Count <> 5 Then WScript.Quit 11
action = arguments(0)
mode = arguments(1)
port = arguments(2)
resultPath = fso.GetAbsolutePathName(arguments(3))
endpoints = arguments(4)

If action <> "Host" And action <> "Join" And action <> "Search" And action <> "Update" Then WScript.Quit 12
If mode <> "Network" And mode <> "Test" Then WScript.Quit 13
If Not IsNumeric(port) Then WScript.Quit 14
If CLng(port) < 1 Or CLng(port) > 65535 Then WScript.Quit 14
If Not fso.FolderExists(fso.GetParentFolderName(resultPath)) Then WScript.Quit 15
If Left(fso.GetFileName(resultPath), 19) <> "Collabsprite-start-" Then WScript.Quit 16
If LCase(Right(resultPath, 7)) <> ".status" Then WScript.Quit 17
If Len(endpoints) > 160 Then WScript.Quit 18
If action = "Update" Then
  If Not ValidVersion(endpoints) Then WScript.Quit 19
Else
  If Not ValidEndpoints(endpoints) Then WScript.Quit 19
End If

If action = "Update" Then
  worker = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Update.ps1")
Else
  worker = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Bootstrap.ps1")
End If
If Not fso.FileExists(worker) Then
  Report "ERROR Startskript fehlt."
  WScript.Quit 1
End If

Report "QUEUED"
If action = "Update" Then
  command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Quote(worker) & _
    " -ResultPath " & Quote(resultPath) & " -InstalledVersion " & Quote(endpoints)
Else
  command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Quote(worker) & _
    " -Action " & action & " -Mode " & mode & " -Port " & port & " -ResultPath " & Quote(resultPath) & " -Endpoints " & Quote(endpoints)
End If
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

Function ValidVersion(value)
  Dim re
  Set re = CreateObject("VBScript.RegExp")
  re.Pattern = "^[0-9]+\.[0-9]+\.[0-9]+(-dev)?$"
  ValidVersion = re.Test(value)
End Function

Function ValidEndpoints(value)
  Dim i, character
  ValidEndpoints = True
  For i = 1 To Len(value)
    character = Mid(value, i, 1)
    If InStr("0123456789.,:", character) = 0 Then
      ValidEndpoints = False
      Exit Function
    End If
  Next
End Function

Sub Report(message)
  Dim output
  Set output = fso.CreateTextFile(resultPath, True, False)
  output.Write message
  output.Close
End Sub
