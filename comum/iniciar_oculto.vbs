' Starts a PowerShell script with NO window (Windows Terminal ignores -WindowStyle Hidden).
' Usage (scheduled task):  wscript.exe //B //Nologo "C:\kcu-automaticos\comum\iniciar_oculto.vbs" "C:\path\script.ps1"
If WScript.Arguments.Count < 1 Then WScript.Quit 1
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & WScript.Arguments(0) & """", 0, False
