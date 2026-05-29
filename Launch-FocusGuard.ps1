$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appScript = Join-Path $appRoot "FocusGuard.ps1"
$logPath = Join-Path $appRoot "launch-log.txt"
$powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

Add-Type -AssemblyName System.Windows.Forms

function Write-LaunchLog {
    param([string]$Message)

    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

try {
    Write-LaunchLog "Launcher started."

    if (-not (Test-Path -LiteralPath $appScript)) {
        Write-LaunchLog "ERROR: FocusGuard.ps1 not found at $appScript"
        [System.Windows.Forms.MessageBox]::Show(
            "FocusGuard.ps1 was not found.`n$appScript",
            "Focus Guard",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        exit 1
    }

    Start-Process -FilePath $powershellPath -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-WindowStyle",
        "Hidden",
        "-File",
        "`"$appScript`""
    ) -WorkingDirectory $appRoot | Out-Null

    Write-LaunchLog "Started FocusGuard.ps1."
}
catch {
    Write-LaunchLog "ERROR: $($_.Exception.Message)"
    [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        "Focus Guard launcher error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}
