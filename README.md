# Aqua Voice Hook

Speak into any app. Aqua Voice Hook listens for your [Aqua Voice](https://aquavoice.com) dictations and takes action the moment they land — pressing Return in terminals, saving transcriptions to clipboard history, or running your own scripts.

## What it does

**Auto-Return** — Dictate into a terminal or chat app and the text is submitted automatically. No reaching for the keyboard. Works with Ghostty, Kitty, iTerm, Terminal, cmux, Cursor, ChatGPT, Claude, and any app you add.

**Clipboard History** — Aqua Voice hides dictations from clipboard managers like Raycast. This app catches them and quietly re-injects them so they show up in your history alongside everything else.

**Shell Hooks** — Run any script after each dictation. The transcribed text arrives as `$1` and through environment variables. Log it, pipe it, trigger a Shortcut — whatever you want.

## Install

Download the latest release, unzip, and drag to `/Applications`:

**[Download Aqua Voice Hook](https://github.com/malpern/aqua-voice-hook/releases/latest)**

On first launch:
1. Grant **Accessibility** permission when prompted (needed for Auto-Return)
2. Grant **Automation** permission for System Events when prompted (needed for keystrokes)

The app runs in the background with an optional menu bar icon (water drop). Updates are checked automatically via Sparkle.

## Settings

Open settings by any of these methods:
- Click the water drop menu bar icon and choose **Settings...**
- Double-click the app in `/Applications`
- Run `open aqua-hook://settings`

### General
- Toggle monitoring on/off
- Save transcriptions to clipboard history (on by default)
- Show or hide the menu bar icon

### Auto-Return
- Toggle on/off and set the delay (default 50ms)
- Manage which apps trigger auto-return
- Add apps from running processes or by bundle ID
- Comes with presets for popular terminals and AI tools

### Hooks
- Add shell scripts that run after each dictation
- Filter hooks to specific apps
- Scripts receive:
  - `$1` — the transcribed text
  - `AQUA_TRANSCRIPTION` — same text via environment
  - `AQUA_FRONTMOST_APP` — the app you dictated into
  - `AQUA_BUNDLE_ID` — that app's bundle identifier
  - `AQUA_TIMESTAMP` — ISO 8601 timestamp

### Status
- Monitor running state and detection count
- See the last dictation text, app, and time

## Configuration

Everything is stored in a single JSON file that agents and scripts can edit directly:

```
~/.config/aqua-voice-hook/config.json
```

```json
{
  "enabled": true,
  "showMenuBarIcon": true,
  "pollIntervalMs": 100,
  "clipboardHistory": true,
  "autoReturn": {
    "enabled": true,
    "delayMs": 50,
    "playSound": true,
    "apps": [
      "com.mitchellh.ghostty",
      "net.kovidgoyal.kitty",
      "com.cmuxterm.app",
      "com.apple.Terminal",
      "com.googlecode.iterm2",
      "com.todesktop.230313mzl4w4u92",
      "com.openai.chat",
      "com.anthropic.claudefordesktop"
    ]
  },
  "hooks": []
}
```

Hook scripts live in `~/.config/aqua-voice-hook/hooks/`.

Changes to the config file are picked up automatically — no restart needed.

## How it works

Aqua Voice inserts text via the clipboard: it writes the transcription (with `org.nspasteboard.TransientType` and `org.nspasteboard.ConcealedType` markers so clipboard managers ignore it), pastes with Cmd+V, then restores the original clipboard ~750ms later.

Aqua Voice Hook detects this by monitoring `NSPasteboard.changeCount` — a +2 jump with Aqua Voice running means a dictation just happened. The +1 jump that follows is the clipboard restore.

On detection:
1. Shell hooks and auto-return fire immediately
2. After the restore completes, the transcription is briefly re-written to the clipboard *without* the hide markers — long enough for Raycast to capture it — then the original clipboard is restored

---

## Building from source

Requires macOS 14+, Swift 5.9+, Apple Silicon.

```bash
git clone https://github.com/malpern/aqua-voice-hook.git
cd aqua-voice-hook
swift build -c release
./Scripts/install.sh
```

The install script builds, assembles the `.app` bundle with Sparkle, code-signs with Developer ID, and installs a LaunchAgent for start-at-login.

## Releasing

```bash
./Scripts/release.sh 0.2.0              # build, sign, notarize, tag, GitHub Release
./Scripts/release.sh --skip-notarize 0.2.0  # local dev build
./Scripts/release.sh --dry-run 0.2.0    # preview steps
```

The release script handles: version bump, release build, code signing (Developer ID + hardened runtime), notarization, Sparkle EdDSA signing, appcast.xml update, git tag, and GitHub Release creation.

## Project structure

```
Sources/AquaVoiceHook/
  main.swift                    # NSApplication entry point
  AppDelegate.swift             # Owns monitor, menu bar, settings, auto-return
  Config.swift                  # JSON config model + file watcher
  PasteboardMonitor.swift       # Clipboard detection + history injection
  HookRunner.swift              # Shell script execution
  SettingsWindowController.swift # NSToolbar settings window
  RunningAppPicker.swift        # App selection sheet
  GroupBox.swift                # Rounded section container
  Info.plist                    # LSUIElement, URL scheme, Sparkle config
  Entitlements.plist            # Apple Events entitlement
```

## License

MIT
