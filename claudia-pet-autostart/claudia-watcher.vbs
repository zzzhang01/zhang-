' Starts claudia-watcher.ps1 with no window.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\claudia-watcher.ps1"""
CreateObject("WScript.Shell").Run cmd, 0, False
