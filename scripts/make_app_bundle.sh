#!/usr/bin/env bash
set -euo pipefail

# make_app_bundle.sh
# Usage: ./scripts/make_app_bundle.sh <path-to-executable> [output-app-path] [bundle-id]
# Example: ./scripts/make_app_bundle.sh .build/x86_64-apple-macosx/debug/Ticklet ./Ticklet.app com.thomas.Ticklet

EXEC_PATH="$1"
OUT_APP_PATH="${2:-./Ticklet.app}"
BUNDLE_ID="${3:-com.yourname.Ticklet}"
ICON_PATH="${4:-}"
# If no icon path is provided, prefer the repo asset at Assets/AppIcon.icns if it exists
if [ -z "$ICON_PATH" ] && [ -f "./Assets/AppIcon.icns" ]; then
  ICON_PATH="./Assets/AppIcon.icns"
  echo "Using repository icon: $ICON_PATH"
fi

if [ ! -f "$EXEC_PATH" ]; then
  echo "Executable not found: $EXEC_PATH" >&2
  exit 2
fi

EXEC_BASENAME=$(basename "$EXEC_PATH")
APP_NAME=$(basename "$OUT_APP_PATH" .app)

CONTENTS="$OUT_APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
INFOPLIST="$CONTENTS/Info.plist"

echo "Creating app bundle at: $OUT_APP_PATH"
rm -rf "$OUT_APP_PATH"
mkdir -p "$MACOS" "$RESOURCES"

# Copy icon if provided
if [ -n "$ICON_PATH" ]; then
  if [ -f "$ICON_PATH" ]; then
    ICON_BASENAME=$(basename "$ICON_PATH")
    cp "$ICON_PATH" "$RESOURCES/$ICON_BASENAME"
    echo "Copied icon to Resources: $ICON_BASENAME"
  else
    echo "Warning: icon file not found: $ICON_PATH" >&2
  fi
fi

# Copy executable
cp "$EXEC_PATH" "$MACOS/$EXEC_BASENAME"
chmod +x "$MACOS/$EXEC_BASENAME"

# Create a minimal Info.plist
cat > "$INFOPLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXEC_BASENAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.0.0</string>
</dict>
</plist>
PLIST

# If an icon was copied into Resources, insert CFBundleIconFile into Info.plist
if [ -n "${ICON_BASENAME:-}" ]; then
  ICON_NAME="${ICON_BASENAME%.*}"
  echo "Adding CFBundleIconFile=$ICON_NAME to Info.plist"
  # Try using plutil to insert; if it fails, fallback to awk insertion before </dict>
  if /usr/bin/plutil -insert CFBundleIconFile -string "$ICON_NAME" "$INFOPLIST" >/dev/null 2>&1; then
    :
  else
    tmp=$(mktemp)
    awk -v key="$ICON_NAME" '{
      if ($0 ~ /<\/dict>/ && !done) {
        print "  <key>CFBundleIconFile</key>"
        print "  <string>" key "</string>"
        done=1
      }
      print $0
    }' "$INFOPLIST" > "$tmp" && mv "$tmp" "$INFOPLIST"
  fi
fi

echo "App bundle created: $OUT_APP_PATH"

cat <<USAGE
Next steps:
 1) Double-click the app ($OUT_APP_PATH) to register it with Launch Services.
 2) Open System Settings → Privacy & Security → Accessibility and add/enable $OUT_APP_PATH.
 3) Quit the app if it's running and then run it again (or run from Finder).

If you are debugging via Xcode, consider granting Accessibility to Xcode instead of the standalone binary.
USAGE
