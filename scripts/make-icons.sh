#!/usr/bin/env bash
# Renders assets/icon.svg (1024x1024, Apple grid: 824 tile at 100,100) into the app's icon
# files. Run via `just icons`. Needs Inkscape and macOS (iconutil). No ImageMagick or Pillow.
# Output:
#   Resources/AppIcon.icns  the bundle icon (full canvas, keeps Apple's margin), 16-1024 px
#   assets/icon/icon.png    the tile alone, 256 px (README, snapshot demo)
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="assets/icon.svg"
WORK="build/icons"

command -v inkscape >/dev/null || { echo "Inkscape not found (brew install --cask inkscape)" >&2; exit 1; }
grep -q 'viewBox="0 0 1024 1024"' "$SRC" || { echo "$SRC must have viewBox=\"0 0 1024 1024\"" >&2; exit 1; }

render() { inkscape "$1" --export-type=png --export-filename="$2" -w "$3" -h "$3" 2>/dev/null; }

mkdir -p assets/icon "$WORK"
rm -rf "${WORK:?}"/*

echo "==> Resources/AppIcon.icns"
ICONSET="$WORK/icon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  render "$SRC" "$ICONSET/icon_${size}x${size}.png" "$size"
  render "$SRC" "$ICONSET/icon_${size}x${size}@2x.png" $((size * 2))
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

echo "==> assets/icon/icon.png"
# The tile without Apple's margin: same drawing, viewBox cropped to the tile.
sed 's/viewBox="0 0 1024 1024"/viewBox="100 100 824 824"/' "$SRC" > "$WORK/tile.svg"
render "$WORK/tile.svg" assets/icon/icon.png 256
