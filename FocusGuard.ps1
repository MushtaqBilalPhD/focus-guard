param(
    [switch]$SelfTest,
    [switch]$Minimized
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Speech
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

if (-not ("FocusGuard.NativeMethods" -as [type])) {
    Add-Type -ReferencedAssemblies "System.Windows.Forms.dll" -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace FocusGuard {
    public delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static class NativeMethods {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

        [DllImport("kernel32.dll")]
        public static extern uint GetTickCount();

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] pRawInputDevices, uint uiNumDevices, uint cbSize);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetRawInputData(IntPtr hRawInput, uint uiCommand, IntPtr pData, ref uint pcbSize, uint cbSizeHeader);
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RAWINPUTDEVICE {
        public ushort usUsagePage;
        public ushort usUsage;
        public int dwFlags;
        public IntPtr hwndTarget;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RAWINPUTHEADER {
        public int dwType;
        public int dwSize;
        public IntPtr hDevice;
        public IntPtr wParam;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct RAWMOUSE {
        [FieldOffset(0)] public ushort usFlags;
        [FieldOffset(4)] public uint ulButtons;
        [FieldOffset(4)] public ushort usButtonFlags;
        [FieldOffset(6)] public ushort usButtonData;
        [FieldOffset(8)] public uint ulRawButtons;
        [FieldOffset(12)] public int lLastX;
        [FieldOffset(16)] public int lLastY;
        [FieldOffset(20)] public uint ulExtraInformation;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RAWINPUT {
        public RAWINPUTHEADER header;
        public RAWMOUSE mouse;
    }

    public static class MouseScrollWatcher {
        private const int WH_MOUSE_LL = 14;
        private const int WM_MOUSEWHEEL = 0x020A;
        private const int WM_MOUSEHWHEEL = 0x020E;
        private static readonly LowLevelMouseProc Proc = HookCallback;
        private static IntPtr hookId = IntPtr.Zero;

        public static uint LastScrollTick = 0;
        public static uint ScrollEvents = 0;
        public static uint RawScrollEvents = 0;

        public static bool Start() {
            if (hookId != IntPtr.Zero) {
                return true;
            }

            using (Process process = Process.GetCurrentProcess())
            using (ProcessModule module = process.MainModule) {
                hookId = NativeMethods.SetWindowsHookEx(
                    WH_MOUSE_LL,
                    Proc,
                    NativeMethods.GetModuleHandle(module.ModuleName),
                    0
                );
            }

            return hookId != IntPtr.Zero;
        }

        public static void Stop() {
            if (hookId != IntPtr.Zero) {
                NativeMethods.UnhookWindowsHookEx(hookId);
                hookId = IntPtr.Zero;
            }
        }

        public static uint MillisecondsSinceLastScroll() {
            if (LastScrollTick == 0) {
                return UInt32.MaxValue;
            }

            return NativeMethods.GetTickCount() - LastScrollTick;
        }

        private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
            if (nCode >= 0) {
                int message = wParam.ToInt32();

                if (message == WM_MOUSEWHEEL || message == WM_MOUSEHWHEEL) {
                    LastScrollTick = NativeMethods.GetTickCount();
                    ScrollEvents++;
                }
            }

            return NativeMethods.CallNextHookEx(hookId, nCode, wParam, lParam);
        }
    }

    public class RawMouseScrollWatcher : NativeWindow {
        private const int WM_INPUT = 0x00FF;
        private const int RIDEV_INPUTSINK = 0x00000100;
        private const int RID_INPUT = 0x10000003;
        private const int RIM_TYPEMOUSE = 0;
        private const ushort RI_MOUSE_WHEEL = 0x0400;
        private const ushort RI_MOUSE_HWHEEL = 0x0800;
        private static readonly RawMouseScrollWatcher Instance = new RawMouseScrollWatcher();
        private static bool started = false;

        public static bool Start(IntPtr handle) {
            if (started) {
                return true;
            }

            Instance.AssignHandle(handle);

            RAWINPUTDEVICE[] devices = new RAWINPUTDEVICE[1];
            devices[0].usUsagePage = 0x01;
            devices[0].usUsage = 0x02;
            devices[0].dwFlags = RIDEV_INPUTSINK;
            devices[0].hwndTarget = handle;

            started = NativeMethods.RegisterRawInputDevices(
                devices,
                (uint)devices.Length,
                (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))
            );

            return started;
        }

        public static void Stop() {
            if (started) {
                Instance.ReleaseHandle();
                started = false;
            }
        }

        protected override void WndProc(ref Message m) {
            if (m.Msg == WM_INPUT) {
                ProcessRawInput(m.LParam);
            }

            base.WndProc(ref m);
        }

        private static void ProcessRawInput(IntPtr rawInputHandle) {
            uint size = 0;
            uint headerSize = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));
            NativeMethods.GetRawInputData(rawInputHandle, RID_INPUT, IntPtr.Zero, ref size, headerSize);

            if (size == 0) {
                return;
            }

            IntPtr buffer = Marshal.AllocHGlobal((int)size);

            try {
                uint copied = NativeMethods.GetRawInputData(rawInputHandle, RID_INPUT, buffer, ref size, headerSize);

                if (copied != size) {
                    return;
                }

                RAWINPUT raw = (RAWINPUT)Marshal.PtrToStructure(buffer, typeof(RAWINPUT));

                if (raw.header.dwType == RIM_TYPEMOUSE &&
                    ((raw.mouse.usButtonFlags & RI_MOUSE_WHEEL) != 0 ||
                     (raw.mouse.usButtonFlags & RI_MOUSE_HWHEEL) != 0)) {
                    MouseScrollWatcher.LastScrollTick = NativeMethods.GetTickCount();
                    MouseScrollWatcher.RawScrollEvents++;
                }
            }
            finally {
                Marshal.FreeHGlobal(buffer);
            }
        }
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

$script:AllowedAppProcesses = @(
    "twitter",
    "x"
)

$script:RoastLines = @()
$script:RoastLines += @'
Listen here, you dusty-ass, thumb-twiddlin' motherfucker. You sittin' there on Twitter like it's your damn job, scrollin' through these bird-brained tweets like some broke fool waitin' on a stimulus check that ain't never comin'. Shut that shit down right now! Close the app, put the phone in the drawer, and get your lazy ass back to work before I come through this screen and slap the Wi-Fi out your life.
'@
$script:RoastLines += @'
You out here actin' like you the CEO of "Let Me See What These Fools Talkin' 'Bout Today." Man, please! Them notifications ain't payin' no bills, them likes ain't fillin' up your gas tank, and them retweets damn sure ain't gon' get you promoted. You got deadlines lookin' at you like "where the fuck is this clown at?" while you out here beefin' with strangers over shit that don't even concern your unemployed behind.
'@
$script:RoastLines += @'
Katt Williams told y'all before: stop playin'! You ain't changin' the world from that couch, you just changin' the brightness on your screen so you can keep doom-scrollin' in the dark like a vampire with no fangs and no future. Get off Twitter, get off Instagram, get off all that nonsense and handle your business, you hear me?
'@
$script:RoastLines += @'
The rent due, the boss lookin', your mama probably callin' askin' when you gon' stop actin' like a whole damn fool. So shut it down, stand up, and go be productive for once in your miserable little life. 'Cause right now you just a waste of good data and oxygen, baby. Now move! Before I roast you again tomorrow when you back on here doin' the same dumb shit. Word to the wise: get to work, fool. Period.
'@
$script:FallbackPhrase = "Close Twitter and do the work."
$script:RoastIndex = 0
$script:IdlePauseSeconds = 30
$script:ScrollActivitySeconds = 3
$script:IsMonitoring = $true
$script:ElapsedSeconds = 0
$script:IsAlerting = $false
$script:Synth = $null
$script:InstanceMutex = $null

function Get-ForegroundInfo {
    $handle = [FocusGuard.NativeMethods]::GetForegroundWindow()
    $titleBuilder = New-Object System.Text.StringBuilder 512
    [void][FocusGuard.NativeMethods]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)

    [uint32]$processId = 0
    [void][FocusGuard.NativeMethods]::GetWindowThreadProcessId($handle, [ref]$processId)

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

function Get-WindowInfoFromHandle {
    param([IntPtr]$Handle)

    $titleBuilder = New-Object System.Text.StringBuilder 512
    [void][FocusGuard.NativeMethods]::GetWindowText($Handle, $titleBuilder, $titleBuilder.Capacity)

    [uint32]$processId = 0
    [void][FocusGuard.NativeMethods]::GetWindowThreadProcessId($Handle, [ref]$processId)

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

function Test-AnyTwitterWindowOpen {
    $script:TwitterWindowFound = $false

    $callback = [FocusGuard.EnumWindowsProc]{
        param([IntPtr]$windowHandle, [IntPtr]$lParam)

        if ($script:TwitterWindowFound) {
            return $false
        }

        if (-not [FocusGuard.NativeMethods]::IsWindowVisible($windowHandle)) {
            return $true
        }

        $windowInfo = Get-WindowInfoFromHandle -Handle $windowHandle
        if (Test-IsTwitterWindow -Title $windowInfo.Title -ProcessName $windowInfo.ProcessName) {
            $script:TwitterWindowFound = $true
            return $false
        }

        return $true
    }

    try {
        [void][FocusGuard.NativeMethods]::EnumWindows($callback, [IntPtr]::Zero)
        return $script:TwitterWindowFound
    }
    finally {
        Remove-Variable -Name TwitterWindowFound -Scope Script -ErrorAction SilentlyContinue
    }
}

function Get-IdleSeconds {
    $lastInput = New-Object FocusGuard.LASTINPUTINFO
    $lastInput.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($lastInput)

    if (-not [FocusGuard.NativeMethods]::GetLastInputInfo([ref]$lastInput)) {
        return 0
    }

    $ticks = [FocusGuard.NativeMethods]::GetTickCount()
    $idleMilliseconds = $ticks - $lastInput.dwTime
    [math]::Max(0, [math]::Round($idleMilliseconds / 1000, 1))
}

function Get-SecondsSinceLastScroll {
    $milliseconds = [FocusGuard.MouseScrollWatcher]::MillisecondsSinceLastScroll()

    if ($milliseconds -eq [uint32]::MaxValue) {
        return [double]::PositiveInfinity
    }

    [math]::Round($milliseconds / 1000, 1)
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

    $isLikelyBrowser = $script:BrowserProcesses -contains $processLower
    $isAllowedApp = $script:AllowedAppProcesses -contains $processLower

    if (-not ($isLikelyBrowser -or $isAllowedApp)) {
        return $false
    }

    return Test-TextLooksLikeTwitter -Text $Title
}

function Test-AnyTwitterBrowserTabOpen {
    $script:TwitterTabFound = $false

    $callback = [FocusGuard.EnumWindowsProc]{
        param([IntPtr]$windowHandle, [IntPtr]$lParam)

        if ($script:TwitterTabFound) {
            return $false
        }

        if (-not [FocusGuard.NativeMethods]::IsWindowVisible($windowHandle)) {
            return $true
        }

        $windowInfo = Get-WindowInfoFromHandle -Handle $windowHandle
        $processLower = ""
        if (-not [string]::IsNullOrWhiteSpace($windowInfo.ProcessName)) {
            $processLower = $windowInfo.ProcessName.ToLowerInvariant()
        }

        if ($script:BrowserProcesses -notcontains $processLower) {
            return $true
        }

        try {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($windowHandle)
            if ($null -eq $root) {
                return $true
            }

            $tabCondition = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::TabItem
            )
            $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)

            for ($i = 0; $i -lt $tabs.Count; $i++) {
                $tabName = $tabs.Item($i).Current.Name
                if (Test-TextLooksLikeTwitter -Text $tabName) {
                    $script:TwitterTabFound = $true
                    return $false
                }
            }
        }
        catch {
            return $true
        }

        return $true
    }

    try {
        [void][FocusGuard.NativeMethods]::EnumWindows($callback, [IntPtr]::Zero)
        return $script:TwitterTabFound
    }
    finally {
        Remove-Variable -Name TwitterTabFound -Scope Script -ErrorAction SilentlyContinue
    }
}

function Format-Clock {
    param([int]$Seconds)

    $minutes = [math]::Floor($Seconds / 60)
    $remaining = $Seconds % 60
    "{0:00}:{1:00}" -f $minutes, $remaining
}

function Shorten-Text {
    param(
        [string]$Text,
        [int]$MaxLength
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "(no active title)"
    }

    if ($Text.Length -le $MaxLength) {
        return $Text
    }

    return $Text.Substring(0, $MaxLength - 3) + "..."
}

function Get-NextRoastLine {
    if ($script:RoastLines.Count -eq 0) {
        return $script:FallbackPhrase
    }

    $line = $script:RoastLines[$script:RoastIndex % $script:RoastLines.Count]
    $script:RoastIndex += 1
    return $line
}

function New-SpeechSsml {
    param([string]$Message)

    $escapedMessage = [System.Security.SecurityElement]::Escape($Message)
@"
<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US">
  <prosody pitch="+35%" rate="+25%" volume="x-loud">
    <emphasis level="strong">$escapedMessage</emphasis>
  </prosody>
</speak>
"@
}

function Invoke-FocusSpeech {
    param([switch]$Force)

    try {
        if ($null -eq $script:Synth) {
            $script:Synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
            $script:Synth.Volume = 100
            $script:Synth.Rate = 5
        }

        if ($Force) {
            $script:Synth.SpeakAsyncCancelAll()
        }

        if ($script:Synth.State -ne [System.Speech.Synthesis.SynthesizerState]::Speaking) {
            $message = Get-NextRoastLine
            try {
                [void]$script:Synth.SpeakSsmlAsync((New-SpeechSsml -Message $message))
            }
            catch {
                [void]$script:Synth.SpeakAsync($message)
            }
        }
    }
    catch {
        [System.Media.SystemSounds]::Exclamation.Play()
    }
}

function Stop-FocusSpeech {
    if ($null -ne $script:Synth) {
        $script:Synth.SpeakAsyncCancelAll()
    }
}

if ($SelfTest) {
    $foreground = Get-ForegroundInfo
    $speechAvailable = $false
    $mouseHookInstalled = [FocusGuard.MouseScrollWatcher]::Start()
    $rawInputForm = New-Object System.Windows.Forms.Form
    $rawInputInstalled = [FocusGuard.RawMouseScrollWatcher]::Start($rawInputForm.Handle)

    try {
        $testSynth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $testSynth.Dispose()
        $speechAvailable = $true
    }
    catch {
        $speechAvailable = $false
    }

    [pscustomobject]@{
        NativeWindowAccess = "OK"
        SpeechAvailable = $speechAvailable
        MouseScrollHook = $(if ($mouseHookInstalled) { "OK" } else { "FAILED" })
        RawScrollInput = $(if ($rawInputInstalled) { "OK" } else { "FAILED" })
        ActiveProcess = $foreground.ProcessName
        ActiveTitle = $foreground.Title
        TwitterWindowOpen = Test-AnyTwitterWindowOpen
        TwitterBrowserTabOpen = Test-AnyTwitterBrowserTabOpen
        IdleSeconds = Get-IdleSeconds
        HookScrollEvents = [FocusGuard.MouseScrollWatcher]::ScrollEvents
        RawScrollEvents = [FocusGuard.MouseScrollWatcher]::RawScrollEvents
    } | Format-List

    [FocusGuard.RawMouseScrollWatcher]::Stop()
    $rawInputForm.Dispose()
    [FocusGuard.MouseScrollWatcher]::Stop()
    exit 0
}

function Stop-ExistingFocusGuardWindows {
    $currentProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id

    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Id -ne $currentProcessId -and
            $_.MainWindowTitle -eq "Focus Guard" -and
            $_.ProcessName -in @("powershell", "pwsh", "WindowsTerminal")
        } |
        ForEach-Object {
            try {
                if (-not $_.CloseMainWindow()) {
                    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                }
                Start-Sleep -Milliseconds 300
                $_.Refresh()
                if (-not $_.HasExited) {
                    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        }
}

Stop-ExistingFocusGuardWindows

$mutexCreated = $false
$script:InstanceMutex = New-Object System.Threading.Mutex($true, "Local\FocusGuardDesktopApp", [ref]$mutexCreated)
if (-not $mutexCreated) {
    [System.Windows.Forms.MessageBox]::Show(
        "Focus Guard is already running. Close the existing Focus Guard window before starting it again.",
        "Focus Guard",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    exit 0
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$mouseHookInstalled = [FocusGuard.MouseScrollWatcher]::Start()

$form = New-Object System.Windows.Forms.Form
$form.Text = "Focus Guard"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(460, 370)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

if ($Minimized) {
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
}

$rawInputInstalled = [FocusGuard.RawMouseScrollWatcher]::Start($form.Handle)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Focus Guard"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(18, 14)
$titleLabel.Size = New-Object System.Drawing.Size(420, 30)
[void]$form.Controls.Add($titleLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Watching for X/Twitter"
$statusLabel.Location = New-Object System.Drawing.Point(21, 52)
$statusLabel.Size = New-Object System.Drawing.Size(410, 22)
$statusLabel.ForeColor = [System.Drawing.Color]::DarkSlateGray
[void]$form.Controls.Add($statusLabel)

$limitLabel = New-Object System.Windows.Forms.Label
$limitLabel.Text = "Limit in minutes"
$limitLabel.Location = New-Object System.Drawing.Point(22, 92)
$limitLabel.Size = New-Object System.Drawing.Size(120, 22)
[void]$form.Controls.Add($limitLabel)

$limitInput = New-Object System.Windows.Forms.NumericUpDown
$limitInput.DecimalPlaces = 1
$limitInput.Increment = [decimal]0.1
$limitInput.Minimum = [decimal]0.1
$limitInput.Maximum = 120
$limitInput.Value = 1
$limitInput.Location = New-Object System.Drawing.Point(150, 90)
$limitInput.Size = New-Object System.Drawing.Size(70, 24)
[void]$form.Controls.Add($limitInput)

$voiceLabel = New-Object System.Windows.Forms.Label
$voiceLabel.Text = "Voice: stern roast loop"
$voiceLabel.Location = New-Object System.Drawing.Point(240, 92)
$voiceLabel.Size = New-Object System.Drawing.Size(200, 22)
$voiceLabel.ForeColor = [System.Drawing.Color]::DarkSlateGray
[void]$form.Controls.Add($voiceLabel)

$scrollModeCheckbox = New-Object System.Windows.Forms.CheckBox
$scrollModeCheckbox.Text = "Debug: require scroll detection"
$scrollModeCheckbox.Checked = $false
$scrollModeCheckbox.Location = New-Object System.Drawing.Point(24, 120)
$scrollModeCheckbox.Size = New-Object System.Drawing.Size(240, 22)
[void]$form.Controls.Add($scrollModeCheckbox)

$timeLabel = New-Object System.Windows.Forms.Label
$timeLabel.Text = "Twitter time: 00:00 / 01:00"
$timeLabel.Location = New-Object System.Drawing.Point(22, 146)
$timeLabel.Size = New-Object System.Drawing.Size(410, 22)
[void]$form.Controls.Add($timeLabel)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(24, 172)
$progress.Size = New-Object System.Drawing.Size(413, 18)
$progress.Minimum = 0
$progress.Maximum = 1000
$progress.Value = 0
[void]$form.Controls.Add($progress)

$scrollLabel = New-Object System.Windows.Forms.Label
$scrollLabel.Text = "Scroll input: waiting..."
$scrollLabel.Location = New-Object System.Drawing.Point(22, 204)
$scrollLabel.Size = New-Object System.Drawing.Size(415, 22)
[void]$form.Controls.Add($scrollLabel)

$activeLabel = New-Object System.Windows.Forms.Label
$activeLabel.Text = "Active window: waiting..."
$activeLabel.Location = New-Object System.Drawing.Point(22, 232)
$activeLabel.Size = New-Object System.Drawing.Size(415, 38)
[void]$form.Controls.Add($activeLabel)

$diagnosticLabel = New-Object System.Windows.Forms.Label
$diagnosticLabel.Text = "Diagnostics: waiting..."
$diagnosticLabel.Location = New-Object System.Drawing.Point(22, 272)
$diagnosticLabel.Size = New-Object System.Drawing.Size(415, 42)
$diagnosticLabel.ForeColor = [System.Drawing.Color]::DimGray
[void]$form.Controls.Add($diagnosticLabel)

$pauseButton = New-Object System.Windows.Forms.Button
$pauseButton.Text = "Pause"
$pauseButton.Location = New-Object System.Drawing.Point(24, 326)
$pauseButton.Size = New-Object System.Drawing.Size(90, 30)
[void]$form.Controls.Add($pauseButton)

$resetButton = New-Object System.Windows.Forms.Button
$resetButton.Text = "Reset"
$resetButton.Location = New-Object System.Drawing.Point(124, 326)
$resetButton.Size = New-Object System.Drawing.Size(90, 30)
[void]$form.Controls.Add($resetButton)

$testButton = New-Object System.Windows.Forms.Button
$testButton.Text = "Test Voice"
$testButton.Location = New-Object System.Drawing.Point(224, 326)
$testButton.Size = New-Object System.Drawing.Size(100, 30)
[void]$form.Controls.Add($testButton)

$quitButton = New-Object System.Windows.Forms.Button
$quitButton.Text = "Quit"
$quitButton.Location = New-Object System.Drawing.Point(347, 326)
$quitButton.Size = New-Object System.Drawing.Size(90, 30)
[void]$form.Controls.Add($quitButton)

$pauseButton.Add_Click({
    $script:IsMonitoring = -not $script:IsMonitoring

    if ($script:IsMonitoring) {
        $pauseButton.Text = "Pause"
        $statusLabel.Text = "Watching for X/Twitter"
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkSlateGray
    }
    else {
        $pauseButton.Text = "Resume"
        $statusLabel.Text = "Paused"
        $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
        Stop-FocusSpeech
    }
})

$resetButton.Add_Click({
    $script:ElapsedSeconds = 0
    $script:IsAlerting = $false
    $progress.Value = 0
    Stop-FocusSpeech
})

$testButton.Add_Click({
    Invoke-FocusSpeech -Force
})

$quitButton.Add_Click({
    $form.Close()
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    $limitSeconds = [math]::Max(1, [int][math]::Round(([double]$limitInput.Value) * 60))
    $requireScroll = $scrollModeCheckbox.Checked
    $timeLabelPrefix = $(if ($requireScroll) { "Scrolling time" } else { "Twitter time" })

    if (-not $script:IsMonitoring) {
        $timeLabel.Text = "${timeLabelPrefix}: $(Format-Clock $script:ElapsedSeconds) / $(Format-Clock $limitSeconds)"
        Stop-FocusSpeech
        return
    }

    $foreground = Get-ForegroundInfo
    $onTwitter = Test-IsTwitterWindow -Title $foreground.Title -ProcessName $foreground.ProcessName
    $twitterWindowOpen = $onTwitter -or (Test-AnyTwitterWindowOpen)
    if ($script:IsAlerting) {
        $twitterWindowOpen = $twitterWindowOpen -or (Test-AnyTwitterBrowserTabOpen)
    }

    $secondsSinceScroll = Get-SecondsSinceLastScroll
    $recentScroll = ($mouseHookInstalled -or $rawInputInstalled) -and ($secondsSinceScroll -le $script:ScrollActivitySeconds)
    $scrollingTwitter = $onTwitter -and $recentScroll
    $focusGuardIsForeground = ($foreground.Title -eq "Focus Guard")
    $twitterContextActive = $onTwitter -or ($focusGuardIsForeground -and $twitterWindowOpen)
    $trackingTwitter = $(if ($requireScroll) { $twitterWindowOpen } else { $twitterContextActive })
    $countingNow = $trackingTwitter -and (-not $requireScroll -or $recentScroll)
    $diagnosticLabel.Text = "Diagnostics: active X=$onTwitter | visible X=$twitterWindowOpen | FG=$focusGuardIsForeground | recent scroll=$recentScroll | count=$countingNow | alert=$($script:IsAlerting)"

    if ($countingNow) {
        $script:ElapsedSeconds += 1
    }

    if (-not $twitterWindowOpen) {
        $script:ElapsedSeconds = 0
        $script:IsAlerting = $false
        Stop-FocusSpeech
    }

    if ($twitterWindowOpen -and $script:ElapsedSeconds -ge $limitSeconds) {
        $script:IsAlerting = $true
    }

    $timeLabel.Text = "${timeLabelPrefix}: $(Format-Clock $script:ElapsedSeconds) / $(Format-Clock $limitSeconds)"
    $activeLabel.Text = "Active window: $(Shorten-Text $foreground.Title 86)"

    if (-not ($mouseHookInstalled -or $rawInputInstalled)) {
        $scrollLabel.Text = "Scroll input: unavailable"
    }
    elseif ($secondsSinceScroll -eq [double]::PositiveInfinity) {
        $scrollLabel.Text = "Scroll input: no scroll seen yet"
    }
    elseif ($recentScroll) {
        $scrollLabel.Text = "Scroll input: detected $(Format-Clock ([math]::Floor($secondsSinceScroll))) ago"
    }
    else {
        $scrollLabel.Text = "Scroll input: last detected $secondsSinceScroll seconds ago"
    }

    $scrollLabel.Text = "$($scrollLabel.Text) | hook=$([FocusGuard.MouseScrollWatcher]::ScrollEvents), raw=$([FocusGuard.MouseScrollWatcher]::RawScrollEvents)"

    if ($limitSeconds -gt 0) {
        $progress.Value = [math]::Min(1000, [int](($script:ElapsedSeconds / $limitSeconds) * 1000))
    }

    if ($script:IsAlerting -and $twitterWindowOpen) {
        $statusLabel.Text = "Over the limit. Close the X/Twitter tab or window to stop the voice."
        $statusLabel.ForeColor = [System.Drawing.Color]::Firebrick
        Invoke-FocusSpeech
    }
    elseif ($countingNow) {
        $remaining = [math]::Max(0, $limitSeconds - $script:ElapsedSeconds)
        if ($requireScroll) {
            $statusLabel.Text = "Counting X/Twitter scrolling. $(Format-Clock $remaining) remaining."
        }
        else {
            $statusLabel.Text = "Counting X/Twitter time. $(Format-Clock $remaining) remaining."
        }
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    }
    elseif ($onTwitter) {
        if ($requireScroll) {
            $statusLabel.Text = "X/Twitter is active. Scroll to count time."
        }
        else {
            $statusLabel.Text = "X/Twitter is active."
        }
        $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    }
    elseif ($focusGuardIsForeground -and $twitterWindowOpen) {
        if ($requireScroll) {
            $statusLabel.Text = "X/Twitter is visible behind Focus Guard. Scroll to count time."
        }
        else {
            $statusLabel.Text = "Counting visible X/Twitter behind Focus Guard."
        }
        $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    }
    elseif ($twitterWindowOpen) {
        $statusLabel.Text = "X/Twitter is open in another window. Timer paused."
        $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    }
    else {
        if ($mouseHookInstalled) {
            $statusLabel.Text = "Watching for X/Twitter scrolling"
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkSlateGray
        }
        else {
            $statusLabel.Text = "Scroll detection failed. Restart the app."
            $statusLabel.ForeColor = [System.Drawing.Color]::Firebrick
        }
    }
})

$form.Add_FormClosed({
    $timer.Stop()
    [FocusGuard.MouseScrollWatcher]::Stop()
    [FocusGuard.RawMouseScrollWatcher]::Stop()
    Stop-FocusSpeech

    if ($null -ne $script:Synth) {
        $script:Synth.Dispose()
    }

    if ($null -ne $script:InstanceMutex) {
        $script:InstanceMutex.ReleaseMutex()
        $script:InstanceMutex.Dispose()
    }
})

$timer.Start()
[void]$form.ShowDialog()
