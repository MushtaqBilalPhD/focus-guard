# Focus Guard

Focus Guard is a Windows-only app at the moment.

A small local Windows desktop utility that sternly roasts you in a high-pitched, commanding voice when you spend more than the chosen time limit on X/Twitter.

## Run it

Double-click:

```text
Start-FocusGuard.bat
```

The Desktop shortcut named `Focus Guard` uses `Launch-FocusGuard.ps1`, which writes launch attempts to `launch-log.txt`.

Or run from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\FocusGuard.ps1
```

For a quick test, set **Limit in minutes** to `0.1`. That triggers after about six seconds.

The default limit is `1` minute.

## Optional ElevenLabs voice

Focus Guard uses Windows text-to-speech by default. To test a more natural ElevenLabs voice:

1. Save your ElevenLabs API key as a local Windows environment variable:

```powershell
setx ELEVENLABS_API_KEY "PASTE-YOUR-API-KEY-HERE"
```

2. Close and reopen PowerShell.
3. Start Focus Guard.
4. Select **ElevenLabs**.
5. Keep the default Voice ID or paste another ElevenLabs Voice ID.
6. Click **Save Voice**, then **Test Voice**.

Generated ElevenLabs audio is cached in `voice-cache` so the same roast chunk is not regenerated every loop. The app stores the Voice ID in `focusguard-settings.json`; it does not store your API key.

## Add a desktop icon

Run this once from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopShortcut.ps1
```

It creates a `Focus Guard` shortcut on your Desktop.

## Start automatically when you open X/Twitter

Run this once from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-AutoStart.ps1
```

This adds a small hidden watcher to your Windows Startup folder. The watcher starts when Windows starts, checks the active browser window every couple of seconds, and opens Focus Guard automatically when it sees X/Twitter.

To turn this off:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-AutoStart.ps1
```

The watcher writes its latest status to `watcher-status.txt` in this folder.

## How it works

- It checks the currently active window once per second.
- By default, it counts time when X/Twitter is active, whether you are scrolling or idle.
- If the Focus Guard window is in front, it can still count time when X/Twitter is visibly open behind it.
- The **Debug: require scroll detection** checkbox is only for testing scroll detection; leave it unchecked for normal use.
- The diagnostics line shows whether it currently detects active X/Twitter, visible X/Twitter, recent scroll input, counting mode, and alert mode.
- After the limit, it loops stern roast lines continuously until the X/Twitter tab or window is no longer detected, or until you pause, reset, or quit the app.
- Click **Edit Roast** in the app to customize the roast script. The app saves custom text to `roast-lines.txt` next to `FocusGuard.ps1`.
- If **ElevenLabs** voice is selected, Focus Guard sends each roast chunk to ElevenLabs once to create an MP3, then reuses the cached file.

## Limits

This is intentionally simple and local. It does not read browser history or log page content. It mainly relies on browser window and tab titles, so it may miss X/Twitter if your browser title does not include `Twitter`, `x.com`, or a title like `Home / X - Google Chrome`.

By default, Focus Guard does not upload anything. If you enable ElevenLabs voice, the roast text is sent to ElevenLabs for speech generation.

If it misses your browser, open X/Twitter, look at the app's "Active window" line, and add that wording to the detection patterns in `FocusGuard.ps1`.

Scroll detection uses both a normal Windows mouse-wheel hook and Windows Raw Input. It should work with a mouse wheel and most touchpads, but unusual input devices or browser extensions can still behave differently.
