Option Explicit

Dim shell, fso, args, token, worker, command, re
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
Set args = WScript.Arguments
If args.Count <> 1 Then WScript.Quit 1
token = args(0)
Set re = CreateObject("VBScript.RegExp")
re.Pattern = "^[a-f0-9]{32}$"
If Not re.Test(token) Then WScript.Quit 2
worker = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Window.ps1")
If Not fso.FileExists(worker) Then WScript.Quit 3
command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & _
  Chr(34) & worker & Chr(34) & " -Token " & token
shell.Run command, 0, False
