Option Explicit
Dim shell, fso, args, mode, token, board, re, worker, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
Set args = WScript.Arguments
If args.Count <> 3 Then WScript.Quit 1
mode = args(0): token = args(1): board = args(2)
If mode <> "Pick" And mode <> "Drop" Then WScript.Quit 2
Set re = New RegExp
re.Pattern = "^[a-f0-9]{32}$"
If Not re.Test(token) Or Not re.Test(board) Then WScript.Quit 2
worker = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "BoardFiles.ps1")
If Not fso.FileExists(worker) Then WScript.Quit 3
command = "powershell.exe -STA -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & _
  Chr(34) & worker & Chr(34) & " -Mode " & mode & " -Token " & token & " -Board " & board
shell.Run command, 0, False
