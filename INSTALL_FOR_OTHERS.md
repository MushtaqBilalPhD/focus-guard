# Focus Guard Install Notes

Focus Guard is a small Windows-only PowerShell app.

## Quick Start

1. Unzip the folder.
2. Open the folder.
3. Double-click `Start-FocusGuard.bat`.

## Optional Desktop Icon

Right-click inside the folder, choose **Open in Terminal**, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopShortcut.ps1
```

## Optional Auto-Start Watcher

To have Focus Guard open automatically when X/Twitter is detected:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-AutoStart.ps1
```

To turn that off:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-AutoStart.ps1
```

## Privacy

Focus Guard runs locally. It checks active window and browser tab titles to detect X/Twitter. It does not read browser history, capture tweets, upload data, or connect to a server.

## Editing the Roast

Click **Edit Roast** in the app. Write one line or paragraph per spoken chunk, with a blank line between chunks. Focus Guard saves your custom script to `roast-lines.txt`.
