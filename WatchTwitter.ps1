param(
    [switch]$SelfTest
)

if (-not ("FocusGuardWatcher.NativeMethods" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

namespace FocusGuardWatcher {
    public static class NativeMethods {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    }
}
"@
}

$script:BrowserProcesses = @(
    "chrome",
    "msedge",
    "firefox",
    "brave",
    "vivaldi",
    "opera",
    "opera_gx",
    "iexplore",
    "arc"
)

$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$focusGuardPath = Join-Path $appRoot "FocusGuard.ps1"
$statusPath = Join-Path $appRoot "watcher-status.txt"
$powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

function Get-ForegroundInfo {
    $handle = [FocusGuardWatcher.NativeMethods]::GetForegroundWindow()
    $titleBuilder = New-Object System.Text.StringBuilder 512
    [void][FocusGuardWatcher.NativeMethods]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)

    [uint32]$processId = 0
    [void][FocusGuardWatcher.NativeMethods]::GetWindowThreadProcessId($handle, [ref]$processId)

    $processName = ""
    if ($processId -gt 0) {
        try {
            $processName = (Get-Process -Id $processId -ErrorAction Stop).ProcessName
        }
        catch {
            $processName = ""
        }
    }

    [pscustomobject]@{
        Title = $titleBuilder.ToString()
        ProcessName = $processName
        ProcessId = $processId
    }
}

function Test-TextLooksLikeTwitter {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $patterns = @(
        "(?i)\btwitter\b",
        "(?i)\bx\.com\b",
        "(?i)\s/\sX(\s|$|-)",
        "(?i)\bon X:",
        "(?i)^X(\s-|$)",
        "(?i)^Home\s/\sX(\s|$|-)",
        "(?i)^Notifications\s/\sX(\s|$|-)",
        "(?i)^Messages\s/\sX(\s|$|-)",
        "(?i)^Profile\s/\sX(\s|$|-)",
        "(?i)^Explore\s/\sX(\s|$|-)",
        "(?i)^Communities\s/\sX(\s|$|-)"
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }

    return $false
}

function Test-IsTwitterWindow {
    param(
        [string]$Title,
        [string]$ProcessName
    )

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return $false
    }

    $processLower = ""
    if (-not [string]::IsNullOrWhiteSpace($ProcessName)) {
        $processLower = $ProcessName.ToLowerInvariant()
    }

    if ($script:BrowserProcesses -notcontains $processLower) {
        return $false
    }

    return Test-TextLooksLikeTwitter -Text $Title
}

function Test-FocusGuardRunning {
    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -eq "Focus Guard" }

    return (($processes | Measure-Object).Count -gt 0)
}

function Start-FocusGuard {
    if (-not (Test-Path -LiteralPath $focusGuardPath)) {
        return
    }

    Start-Process -FilePath $powershellPath -WindowStyle Hidden -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$focusGuardPath`"",
        "-Minimized"
    ) | Out-Null
}

function Write-WatcherStatus {
    param(
        [object]$Foreground,
        [bool]$TwitterActive,
        [bool]$GuardRunning,
        [string]$Action
    )

    $status = @(
        "Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "ActiveProcess: $($Foreground.ProcessName)",
        "ActiveTitle: $($Foreground.Title)",
        "TwitterActive: $TwitterActive",
        "FocusGuardRunning: $GuardRunning",
        "Action: $Action"
    ) -join [Environment]::NewLine

    Set-Content -LiteralPath $statusPath -Value $status -Encoding UTF8
}

$foreground = Get-ForegroundInfo
$twitterActive = Test-IsTwitterWindow -Title $foreground.Title -ProcessName $foreground.ProcessName
$guardRunning = Test-FocusGuardRunning

if ($SelfTest) {
    [pscustomobject]@{
        ActiveProcess = $foreground.ProcessName
        ActiveTitle = $foreground.Title
        TwitterActive = $twitterActive
        FocusGuardRunning = $guardRunning
        FocusGuardPath = $focusGuardPath
        StatusPath = $statusPath
    } | Format-List
    exit 0
}

$mutexCreated = $false
$watcherMutex = New-Object System.Threading.Mutex($true, "Local\FocusGuardTwitterWatcher", [ref]$mutexCreated)
if (-not $mutexCreated) {
    exit 0
}

try {
    Write-WatcherStatus -Foreground $foreground -TwitterActive $twitterActive -GuardRunning $guardRunning -Action "Watcher started"

    while ($true) {
        $foreground = Get-ForegroundInfo
        $twitterActive = Test-IsTwitterWindow -Title $foreground.Title -ProcessName $foreground.ProcessName
        $guardRunning = Test-FocusGuardRunning
        $action = "Waiting"

        if ($twitterActive -and -not $guardRunning) {
            Start-FocusGuard
            $action = "Started Focus Guard"
            Start-Sleep -Seconds 5
        }

        Write-WatcherStatus -Foreground $foreground -TwitterActive $twitterActive -GuardRunning $guardRunning -Action $action
        Start-Sleep -Seconds 2
    }
}
finally {
    if ($null -ne $watcherMutex) {
        $watcherMutex.ReleaseMutex()
        $watcherMutex.Dispose()
    }
}
