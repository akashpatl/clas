#!/usr/bin/env bash
# Generate Resources/AppIcon.icns from docs/logo.png.
#
# macOS .icns files bundle multiple sizes. iconutil + an iconset folder
# is the canonical way to build them. Sizes per Apple's HIG: 16/32/128/
# 256/512 logical, with @2x retina variants.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/docs/logo.png"
ICONSET="$ROOT/dist/AppIcon.iconset"
OUT="$ROOT/Resources/AppIcon.icns"

mkdir -p "$ROOT/Resources" "$(dirname "$ICONSET")"
rm -rf "$ICONSET"
mkdir "$ICONSET"

# 16, 32, 128, 256, 512 logical sizes; @2x = double pixel size.
sips -z 16   16   "$SRC" --out "$ICONSET/icon_16x16.png"     >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_16x16@2x.png"  >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_32x32.png"     >/dev/null
sips -z 64   64   "$SRC" --out "$ICONSET/icon_32x32@2x.png"  >/dev/null
sips -z 128  128  "$SRC" --out "$ICONSET/icon_128x128.png"   >/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_128x128@2x.png">/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_256x256.png"   >/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_256x256@2x.png">/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_512x512.png"   >/dev/null
cp "$SRC" "$ICONSET/icon_512x512@2x.png"  # already 1024×1024

iconutil -c icns "$ICONSET" -o "$OUT"
echo "Built ${OUT}"
ls -lh "$OUT"
