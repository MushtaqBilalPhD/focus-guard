$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$watcherScript = Join-Path $appRoot "WatchTwitter.ps1"
$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "Focus Guard Watcher.lnk"
$powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershellPath
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watcherScript`""
$shortcut.WorkingDirectory = $appRoot
$shortcut.Description = "Start Focus Guard automatically when X/Twitter is opened"
$shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,101"
$shortcut.Save()

$alreadyRunning = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
    Where-Object { $_.CommandLine -like "*WatchTwitter.ps1*" }

if (-not $alreadyRunning) {
    Start-Process -FilePath $powershellPath -WindowStyle Hidden -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$watcherScript`""
    ) | Out-Null
}

Write-Host "Created Startup shortcut: $shortcutPath"
Write-Host "Focus Guard watcher is running."
