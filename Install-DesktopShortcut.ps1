$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcherScript = Join-Path $appRoot "Launch-FocusGuard.ps1"
$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop "Focus Guard.lnk"
$powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershellPath
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherScript`""
$shortcut.WorkingDirectory = $appRoot
$shortcut.Description = "Start Focus Guard"
$shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,101"
$shortcut.Save()

Write-Host "Created desktop shortcut: $shortcutPath"
