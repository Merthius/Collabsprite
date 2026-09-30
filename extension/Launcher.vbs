Option Explicit

Dim fso, shell, arguments, action, mode, port, resultPath, endpoints, worker, command, ownerPid, ownerToken, re
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
Set arguments = WScript.Arguments

If arguments.Count <> 5 And arguments.Count <> 6 Then WScript.Quit 11
action = arguments(0)
mode = arguments(1)
port = arguments(2)
resultPath = fso.GetAbsolutePathName(arguments(3))
endpoints = arguments(4)
ownerToken = ""
If arguments.Count = 6 Then
  ownerToken = arguments(5)
  Set re = New RegExp
  re.Pattern = "^[a-f0-9]{32}$"
  If action <> "Host" Or Not re.Test(ownerToken) Then WScript.Quit 20
End If

If action <> "Host" And action <> "Join" And action <> "Search" And action <> "Update" Then WScript.Quit 12
If mode <> "Network" And mode <> "Test" Then WScript.Quit 13
If Not IsNumeric(port) Then WScript.Quit 14
If CLng(port) < 1 Or CLng(port) > 65535 Then WScript.Quit 14
If Not fso.FolderExists(fso.GetParentFolderName(resultPath)) Then WScript.Quit 15
If Left(fso.GetFileName(resultPath), Len("Collabsprite-start-")) <> "Collabsprite-start-" Then WScript.Quit 16
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
  ownerPid = 0
  ' Native UI calls pass their exact window token. Resolve its PID entirely in
  ' the detached worker, never wait for slow WMI on Aseprite's UI thread.
  ' The legacy ancestry path is retained for batch mode / single-window UI.
  If action = "Host" And ownerToken = "" Then ownerPid = FindAsepriteOwner()
  command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Quote(worker) & _
    " -Action " & action & " -Mode " & mode & " -Port " & port & " -ResultPath " & Quote(resultPath) & " -Endpoints " & Quote(endpoints) & " -OwnerPid " & ownerPid
  If ownerToken <> "" Then command = command & " -OwnerToken " & ownerToken
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

Function FindAsepriteOwner()
  ' Only this unique launcher and its real ancestors, never other Aseprites.
  On Error Resume Next
  Dim service, candidates, proc, current, matches, parents, parent, depth
  FindAsepriteOwner = 0
  Set service = GetObject("winmgmts:\\.\root\cimv2")
  Set candidates = service.ExecQuery("SELECT ProcessId,ParentProcessId,Name,CommandLine,CreationDate FROM Win32_Process WHERE Name='wscript.exe' OR Name='cscript.exe'")
  matches = 0
  For Each proc In candidates
    If InStr(1, Replace(CStr(proc.CommandLine), "/", "\"), resultPath, vbTextCompare) > 0 Then
      Set current = proc
      matches = matches + 1
    End If
  Next
  If Err.Number <> 0 Or matches <> 1 Then Exit Function
  For depth = 1 To 8
    Set parents = service.ExecQuery("SELECT ProcessId,ParentProcessId,Name,CreationDate FROM Win32_Process WHERE ProcessId=" & CLng(current.ParentProcessId))
    If Err.Number <> 0 Or parents.Count <> 1 Then Exit Function
    For Each parent In parents
      If CStr(parent.CreationDate) > CStr(current.CreationDate) Then Exit Function
      If LCase(parent.Name) = "aseprite.exe" Then
        FindAsepriteOwner = CLng(parent.ProcessId)
        Exit Function
      End If
      Set current = parent
    Next
  Next
  On Error GoTo 0
End Function

Function ValidVersion(value)
  Dim re
  Set re = CreateObject("VBScript.RegExp")
  re.Pattern = "^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*)?$"
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
