#!/usr/bin/env bash
# Build CLAS as a proper macOS .app bundle and zip it for distribution.
#
# Output: dist/CLAS-<version>.zip containing CLAS.app + SETUP.md
# Usage:  ./scripts/bundle.sh [version]   (default: 0.1.0)
#
# Why a wrapper instead of just shipping the SPM binary:
#  - macOS notifications, dock-hide, and bundle ID all require a real .app
#  - LSUIElement in Info.plist is what makes us a menu-bar accessory
#  - ad-hoc codesign keeps macOS happy enough to launch unsigned downloads
#    (after the user right-clicks → Open the first time)

set -euo pipefail

VERSION="${1:-0.1.0}"
BIN="CLAS"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/dist/${BIN}.app"
ZIP="${ROOT}/dist/CLAS-${VERSION}.zip"

cd "$ROOT"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp ".build/release/${BIN}" "$APP/Contents/MacOS/${BIN}"
cp hooks/notify-sidebar.sh "$APP/Contents/Resources/notify-sidebar.sh"
chmod +x "$APP/Contents/Resources/notify-sidebar.sh"

# Copy SPM-generated resource bundles to the .app ROOT (not Contents/Resources).
# Reason: SPM emits a `resource_bundle_accessor.swift` per package that resolves
# bundles via `Bundle.main.bundleURL.appendingPathComponent(...)`, which on
# macOS is the .app directory itself (not Contents/Resources). Without this
# step, KeyboardShortcuts crashes on first hotkey access trying to load its
# resources from /Applications/CLAS.app/<Pkg>_<Pkg>.bundle.
shopt -s nullglob
for b in .build/release/*.bundle; do
    cp -R "$b" "$APP/"
done
shopt -u nullglob

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>${BIN}</string>
    <key>CFBundleIdentifier</key><string>xyz.patl.clas</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>CLAS</string>
    <key>CFBundleDisplayName</key><string>CLAS</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>CLAS uses AppleScript to bring the right Ghostty tab to the front when you click a session.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
# codesign emits a non-zero exit on the "unsealed contents present in the
# bundle root" warning that fires because SPM resource bundles live at
# the .app root (outside Contents/). Cosmetic for ad-hoc signing — the
# .app still launches via the right-click → Open flow — so don't fail
# the script. A future Apple Developer ID + notarisation pass will need
# to address this properly (likely by symlinking the bundle or patching
# the SPM accessor).
codesign --force --deep --sign - "$APP" 2>&1 || true

echo "==> Generating SETUP.md"
cat > "${ROOT}/dist/SETUP.md" <<'MD'
# CLAS — Install

1. Drag **CLAS.app** to `/Applications/`.
2. **First launch:** right-click the app → **Open** → click *Open* again. macOS will
   complain about an unidentified developer (CLAS isn't notarised yet); the
   right-click trick bypasses that one time. Subsequent launches just work.
3. You'll see a hollow circle in the menu bar — that's CLAS, watching for
   sessions that need you.

## Wire up the instant-notification hook (recommended)

Add the hook to `~/.claude/settings.json`. Preserve any existing entries
under `hooks.Notification`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/Applications/CLAS.app/Contents/Resources/notify-sidebar.sh"
          }
        ]
      }
    ]
  }
}
```

Without the hook, CLAS still works — the filesystem watcher catches everything
within ~500ms.

## First-run permissions

When you click a session row for the first time, macOS will prompt:

> "CLAS" wants to control "Ghostty"

Click **OK**. This grants AppleScript automation so CLAS can focus the right
Ghostty tab. You can revoke it later in **System Settings → Privacy & Security
→ Automation**.

## Hotkey

Default: **⌥ Space** (option-space). Click the menu bar icon for the popover
and use the recorder to rebind.

## Quitting

Click the menu bar icon → **Quit**, or `pkill CLAS` from a terminal.
MD

echo "==> Zipping"
rm -f "$ZIP"
(cd "${ROOT}/dist" && zip -qry "$(basename "$ZIP")" "${BIN}.app" SETUP.md)

echo
echo "Built: ${ZIP}"
ls -lh "$ZIP"
