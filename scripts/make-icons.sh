#!/usr/bin/env bash
# Renders assets/icon.svg (1024x1024, Apple grid: 824 tile at 100,100) into icon files, then
# copies the macOS one to Resources/AppIcon.icns for scripts/bundle.sh. Run via `just icons`.
#
#   make-icons.sh [<icon.svg> <out-dir>] [--work DIR]   (defaults: assets/icon.svg assets/icon)
#
# Needs Inkscape; icon.icns also needs macOS (iconutil). No ImageMagick or Pillow.
# Output in <out-dir>:
#   icon.icns  macOS bundle icon (full canvas, keeps Apple's margin), 16-1024 px
#   icon.ico   Windows icon (tile only), 16-256 px, PNG-compressed entries
#   icon.png   window/Linux icon (tile only), 256 px
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="assets/icon.svg"; OUT="assets/icon"
if [[ $# -ge 2 && "$1" != --* ]]; then SRC="$1"; OUT="$2"; shift 2; fi
WORK="build/icons"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --work) WORK="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

command -v inkscape >/dev/null || { echo "Inkscape not found (brew install --cask inkscape)" >&2; exit 1; }
grep -q 'viewBox="0 0 1024 1024"' "$SRC" || { echo "$SRC must have viewBox=\"0 0 1024 1024\"" >&2; exit 1; }

render() { inkscape "$1" --export-type=png --export-filename="$2" -w "$3" -h "$3" 2>/dev/null; }

mkdir -p "$OUT" "$WORK"
rm -rf "${WORK:?}"/*

# The tile without Apple's margin: same drawing, viewBox cropped to the tile.
sed 's/viewBox="0 0 1024 1024"/viewBox="100 100 824 824"/' "$SRC" > "$WORK/tile.svg"

if command -v iconutil >/dev/null; then
  echo "==> icon.icns"
  ICONSET="$WORK/icon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    render "$SRC" "$ICONSET/icon_${size}x${size}.png" "$size"
    render "$SRC" "$ICONSET/icon_${size}x${size}@2x.png" $((size * 2))
  done
  iconutil -c icns "$ICONSET" -o "$OUT/icon.icns"
else
  echo "==> skipping icon.icns (iconutil is macOS only)"
fi

echo "==> icon.ico, icon.png"
for size in 16 24 32 48 64 128 256; do
  render "$WORK/tile.svg" "$WORK/tile-$size.png" "$size"
done
cp "$WORK/tile-256.png" "$OUT/icon.png"
# An ICO is a directory of PNG images (supported since Windows Vista); 256 is stored as 0.
python3 - "$WORK" "$OUT/icon.ico" <<'PY'
import struct, sys
work, out = sys.argv[1], sys.argv[2]
sizes = [16, 24, 32, 48, 64, 128, 256]
images = [open(f"{work}/tile-{s}.png", "rb").read() for s in sizes]
offset = 6 + 16 * len(sizes)
data = struct.pack("<HHH", 0, 1, len(sizes))
for size, png in zip(sizes, images):
    data += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(png), offset)
    offset += len(png)
open(out, "wb").write(data + b"".join(images))
PY

ls -la "$OUT"

cp "$OUT/icon.icns" Resources/AppIcon.icns
echo "Updated Resources/AppIcon.icns"
