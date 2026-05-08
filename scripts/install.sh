#!/usr/bin/env bash
# Build CLAS, replace /Applications/CLAS.app, relaunch.
#
# Usage:
#   ./scripts/install.sh                # version stamp = dev-<timestamp>
#   ./scripts/install.sh 0.1.3          # explicit version
#
# What it does:
#  1. swift build + bundle .app via scripts/bundle.sh
#  2. kill any running CLAS instance (bundled or SPM-binary)
#  3. rm -rf /Applications/CLAS.app && cp -R dist/CLAS.app /Applications/
#  4. open the new /Applications/CLAS.app
#
# Why /Applications: a friend installs CLAS there (per release SETUP.md),
# so running the same path on the dev machine matches the production
# experience — including the AppleScript-control TCC prompt path.

set -euo pipefail

VERSION="${1:-dev-$(date +%Y%m%d-%H%M%S)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="/Applications/CLAS.app"

"$ROOT/scripts/bundle.sh" "$VERSION"

echo "==> Quitting any running CLAS"
pkill -f 'CLAS\.app/Contents/MacOS/CLAS' 2>/dev/null || true
pkill -f '\.build/release/CLAS$' 2>/dev/null || true
# Give launchd a moment to reap the process so the .app file isn't held open.
sleep 0.5

echo "==> Replacing $DEST"
rm -rf "$DEST"
cp -R "$ROOT/dist/CLAS.app" "$DEST"

echo "==> Launching"
open "$DEST"

echo
echo "Installed CLAS ${VERSION} at ${DEST}"
echo "Look for the menu-bar icon."
