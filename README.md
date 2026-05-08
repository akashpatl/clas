# CLAS — Claude Sessions

A native macOS menu-bar app that shows you which Claude Code sessions need your attention, and gets you back to them in one keystroke.

> If you run more than one `claude` at a time across terminal tabs, you've probably caught yourself glancing at the wrong window for a few seconds before realising the prompt was waiting on you somewhere else. CLAS exists for that.

<!-- TODO: add a screenshot of the menu bar item with count, the popover, and the HUD. -->

<img width="724" height="519" alt="clas_expanded_sanitized" src="https://github.com/user-attachments/assets/17b7edb3-b425-4ef2-96d9-659a6e78d37a" />

<img width="479" height="393" alt="clas_compact_sanitized" src="https://github.com/user-attachments/assets/a053924f-4f46-4b6d-a1cd-79b528f73667" />



## What it does

- **Menu bar indicator.** A solid orange `●` with a count when one or more sessions need you. Hollow `○` otherwise.
- **Floating HUD.** Hit a global hotkey (default ⌥Space) to see every active Claude session — sorted with the ones that need you on top — and press ↩ to jump straight to that terminal tab.
- **Native banners.** When a session transitions to "needs your attention", you get a system notification with the session's name, working directory, and what it's waiting on.
- **Click to address.** Click any row (in the popover or the HUD) and CLAS focuses that exact Ghostty tab and silently dismisses it from the count. The dismissal expires automatically the next time Claude does something new in that session.

## How it knows

CLAS reads two things:

1. **`~/.claude/sessions/*.json`** — Claude Code itself writes one JSON per running session with `status`, `cwd`, `name`, and (when relevant) what it's waiting on. CLAS polls this directory every 500 ms.
2. **A `Notification` hook** (optional but recommended) — a tiny shell script POSTs to a localhost HTTP listener inside the app whenever Claude needs you, so the UI updates within a few ms instead of waiting for the next poll.

That's the whole data pipeline. No private APIs, no scraping, no agents-running-agents.

## Requirements

- macOS 14 (Sonoma) or later
- [Ghostty](https://ghostty.org) — for click-to-focus. Other terminals are not yet supported (PRs welcome).
- A working `claude` CLI (Claude Code).
- Xcode 15+ / Swift 6 toolchain to build from source.

## Install

Until binary releases ship, build from source:

```bash
git clone https://github.com/akashpatl/clas.git
cd clas
swift build -c release
```

Run the app:

```bash
.build/release/CLAS &
```

The app is a pure menu-bar accessory — no Dock icon. You'll see a hollow circle in the menu bar.

### Wire up the instant-notification hook (recommended)

Add the Notification hook to `~/.claude/settings.json` (preserve any existing entries):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/clas/hooks/notify-sidebar.sh"
          }
        ]
      }
    ]
  }
}
```

Replace `/absolute/path/to/clas` with wherever you cloned the repo. The script always exits 0, so if CLAS isn't running it's a silent no-op.

Without the hook, CLAS still works — the filesystem polling catches everything within 500 ms.

## Usage

**Menu bar icon**
- Hollow circle: no sessions need you
- Solid orange circle + number: that many sessions are waiting on you

**Click the menu bar icon** for the popover: full session list, the global hotkey recorder, and Quit.

**Press ⌥Space** (rebindable in the popover) for the HUD overlay:
- `↑` / `↓` — move selection
- `↩` — focus the selected session's Ghostty tab
- `⎋` — dismiss the HUD without selecting

**Click any row** (popover or HUD) to focus that session's Ghostty tab and dismiss it from the count.

## How "needs your attention" is decided

A session counts toward the indicator when **either** of these is true:

1. Claude reports `status: waiting` (formal permission prompt or `AskUserQuestion`)
2. Claude's most recent visible message was an assistant message AND the session is otherwise idle (claude finished talking, isn't working — ball in your court)

Once you address a session (click its row), it's silently dismissed from the count. The dismissal expires automatically the next time `updatedAt` advances — i.e. the next time Claude does anything new — so a session always re-arms itself if there's something new to look at.

The predicate lives in `Sources/CLAS/Model/AttentionTracker.swift` and is intentionally compact (~5 lines) so you can refine it to your taste.

## Project layout

```
Sources/CLAS/
├── CLASApp.swift                # @main, AppDelegate, scene wiring
├── Model/                       # Pure data + state
│   ├── Session.swift            # Mirror of ~/.claude/sessions/*.json
│   ├── SessionStore.swift       # @Observable store + diff event types
│   └── AttentionTracker.swift   # "Ball in your court" predicate + dismissals
├── Services/                    # I/O against the outside world
│   ├── SessionsDirWatcher.swift # 500ms poll of ~/.claude/sessions/
│   ├── TranscriptReader.swift   # Tail-read JSONL for last visible message
│   └── HookHTTPListener.swift   # 127.0.0.1 listener for the hook ping
├── UI/                          # All SwiftUI / NSPanel surfaces
│   ├── MenuBarLabel.swift       # The status item icon
│   ├── MenuBarView.swift        # Popover content
│   ├── HUDPanel.swift           # NSPanel hosting the HUD
│   ├── HUDView.swift            # HUD SwiftUI body + keyboard nav
│   ├── HUDController.swift      # Show/hide + positioning
│   └── HotkeyName.swift         # KeyboardShortcuts identifier + default
├── Terminal/
│   ├── AppleScriptString.swift  # Safe AppleScript string escaping
│   └── GhosttyFocuser.swift     # Brings the right Ghostty tab to front
└── Notifications/
    └── Notifier.swift           # System banner via osascript
```

## Status

Pre-1.0. Works on the author's machine; expect rough edges. Things known to be unfinished:

- Only Ghostty is wired up for click-to-focus. iTerm2 / Terminal.app / Warp are not yet supported.
- Not packaged as a `.app` bundle. The SPM build runs as a bare executable, which means notifications come from `osascript` rather than `UNUserNotificationCenter`. No deep-link from notification banners.
- No autostart-at-login wiring.

## Contributing

Issues and PRs welcome once the repo goes public. Until then, this is a personal scratchpad — feel free to fork.

## License

MIT — see [LICENSE](LICENSE).
