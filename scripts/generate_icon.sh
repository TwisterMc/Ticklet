#!/usr/bin/env bash
# generate_icon.sh - Create a multi-resolution .icns file for macOS from a 512x512 source PNG
# Usage: ./scripts/generate_icon.sh [source_png]
# Example: ./scripts/generate_icon.sh Assets/src/icon-512.png

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/../Assets"
SOURCE_PNG="${1:-$ASSETS_DIR/src/icon-512.png}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

if [ ! -f "$SOURCE_PNG" ]; then
  echo "Error: Source PNG not found: $SOURCE_PNG"
  exit 1
fi

echo "Using source icon: $SOURCE_PNG"
echo "Generating icon sizes in $TEMP_DIR..."

# Required sizes for .icns format
# Using sips (scriptable image processing system) - built into macOS
sizes=(16 32 64 128 256 512 1024)

for size in "${sizes[@]}"; do
  output_png="$TEMP_DIR/icon_${size}.png"
  sips -z "$size" "$size" "$SOURCE_PNG" --out "$output_png" &> /dev/null
  echo "  Created ${size}x${size}"
done

echo ""
echo "Converting to .icns format..."

# Create iconset directory with proper naming for iconutil
ICONSET_DIR="$TEMP_DIR/Ticklet.iconset"
mkdir -p "$ICONSET_DIR"

# Map generated PNGs to .iconset naming convention
# Format: icon_<width>x<height>[<scale>].png
cp "$TEMP_DIR/icon_16.png"    "$ICONSET_DIR/icon_16x16.png"
cp "$TEMP_DIR/icon_32.png"    "$ICONSET_DIR/icon_16x16@2x.png"
cp "$TEMP_DIR/icon_32.png"    "$ICONSET_DIR/icon_32x32.png"
cp "$TEMP_DIR/icon_64.png"    "$ICONSET_DIR/icon_32x32@2x.png"
cp "$TEMP_DIR/icon_128.png"   "$ICONSET_DIR/icon_128x128.png"
cp "$TEMP_DIR/icon_256.png"   "$ICONSET_DIR/icon_128x128@2x.png"
cp "$TEMP_DIR/icon_256.png"   "$ICONSET_DIR/icon_256x256.png"
cp "$TEMP_DIR/icon_512.png"   "$ICONSET_DIR/icon_256x256@2x.png"
cp "$TEMP_DIR/icon_512.png"   "$ICONSET_DIR/icon_512x512.png"
cp "$TEMP_DIR/icon_1024.png"  "$ICONSET_DIR/icon_512x512@2x.png"

# Convert iconset to .icns using iconutil (from Xcode Command Line Tools)
if command -v iconutil &> /dev/null; then
  iconutil -c icns "$ICONSET_DIR" -o "$ASSETS_DIR/AppIcon.icns"
  echo "✓ Generated AppIcon.icns with all required Retina resolutions"
  echo "  Location: $ASSETS_DIR/AppIcon.icns"
  ls -lh "$ASSETS_DIR/AppIcon.icns"
else
  echo "Error: iconutil not found. Install Xcode Command Line Tools with:"
  echo "  xcode-select --install"
  exit 1
fi
