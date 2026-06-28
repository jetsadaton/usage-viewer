# UsageViewer

macOS menu bar app that shows Claude and ChatGPT/Codex quota at a glance.

```
🟢C:17%/10% · 🟢G:1%
```

![menu bar preview](https://placeholder)

## Features

- **Menu bar display** — live quota in 4 styles: `%`, `Bar`, `Dot` (color-coded), `Compact`
- **Claude** — 5-hour and 7-day quota with progress bars and reset countdown
- **ChatGPT / Codex** — primary and secondary rate-limit windows
- **Auto-detects session key** from Claude Desktop, Chrome, Arc, or Brave — no manual copy-paste
- **Color coding** — 🟢 < 70% · 🟡 70–89% · 🔴 ≥ 90%
- **Stale data** — keeps last known numbers visible when offline or on error
- **Wake-from-sleep refresh** — updates immediately when Mac wakes up
- **Auto-retry** — exponential backoff on transient network errors
- **Re-detect button** — one tap to refresh an expired Claude session key
- **Display settings** — toggle each provider, quota window, and menu bar style
- **ESP32 push** _(optional)_ — POST quota data to an ESP32 TFT display after each refresh

## Requirements

- macOS 14 Sonoma or later
- Xcode Command Line Tools
- Claude account (claude.ai Pro/Team)
- ChatGPT / Codex CLI _(optional — needs `~/.codex/auth.json`)_

## Install

### Quick (recommended)

```bash
git clone https://github.com/yourname/usage-viewer
cd usage-viewer
make open
```

`make open` builds a release binary, wraps it into `UsageViewer.app`, and launches it.

### First launch

1. A Keychain dialog appears: **"Claude Safe Storage"** — click **Always Allow**  
   _(one-time only — lets the app read your Claude Desktop session key)_
2. The menu bar updates within a few seconds.

### Run at login

```bash
cp -r UsageViewer.app /Applications/
```

Then: **System Settings → General → Login Items** → add `UsageViewer`.

## Claude session key

The app tries these sources in order:

| Priority | Source                                                          |
| -------- | --------------------------------------------------------------- |
| 1        | Claude Desktop (`~/Library/Application Support/Claude/Cookies`) |
| 2        | Chrome cookies                                                  |
| 3        | Arc / Brave / Edge cookies                                      |
| 4        | Manual paste in Settings                                        |

If the key expires, a **Re-detect** button appears in the popover — tap it to refresh automatically.

## ChatGPT / Codex

Reads `~/.codex/auth.json` created by the [Codex CLI](https://github.com/openai/codex).

```bash
codex login   # authenticate once
```

No extra configuration needed after that.

## Settings

Open the popover → gear icon (⚙).

| Section         | Options                                            |
| --------------- | -------------------------------------------------- |
| Claude          | Auto-detect or paste session key manually          |
| ChatGPT / Codex | Shows auth file status                             |
| Display         | Show/hide providers, quota windows, menu bar style |
| ESP32 Display   | Enable + set IP for external TFT display           |

### Menu bar styles

| Style     | Example         |
| --------- | --------------- |
| `%`       | `C:17%/10%`     |
| `Bar`     | `C:███░░/██░░░` |
| `Dot`     | `🟢C:17%/10%`   |
| `Compact` | `17%/10%`       |

## ESP32 external display _(optional)_

Connect an ESP32 + 2.8" TFT (ILI9341) to your local network. Enable in Settings and enter its IP — the app will POST quota data to `http://<ip>:8765/usage` after every refresh.

Payload:

```json
{
  "claude5h": 17,
  "claude7d": 10,
  "claude_resets_in": 5580,
  "codex": 1,
  "ts": 1719561234
}
```

Firmware guide: see `docs/esp32-firmware.md` _(coming soon)_.

## Build commands

```bash
make build    # swift build -c release
make install  # build + create UsageViewer.app bundle
make open     # install + launch
make clean    # remove build artifacts
```

## Tech stack

- Swift 5.9 · SwiftUI + AppKit · Swift Package Manager
- macOS 14+ · `NSStatusItem` · `NSPopover`
- CommonCrypto — PBKDF2 + AES-128-CBC for browser cookie decryption
- No third-party dependencies

## Credentials storage

Session key is stored at `~/.config/usage-viewer/credentials.json` (mode `600`) — not in Keychain, to avoid unsigned-app access dialogs on every launch.
