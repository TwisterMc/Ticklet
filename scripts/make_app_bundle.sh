#!/usr/bin/env bash
set -euo pipefail

# make_app_bundle.sh
# Usage: ./scripts/make_app_bundle.sh <path-to-executable> [output-app-path] [bundle-id]
# Example: ./scripts/make_app_bundle.sh .build/x86_64-apple-macosx/debug/Ticklet ./Ticklet.app com.thomas.Ticklet

EXEC_PATH="$1"
OUT_APP_PATH="${2:-./Ticklet.app}"
BUNDLE_ID="${3:-com.yourname.Ticklet}"
# Prefer the repo asset at Assets/AppIcon.icns when present; do not use a passed icon path
if [ -f "./Assets/AppIcon.icns" ]; then
  ICON_PATH="./Assets/AppIcon.icns"
  echo "Using repository icon: $ICON_PATH"
else
  ICON_PATH=""
fi

if [ ! -f "$EXEC_PATH" ]; then
  echo "Executable not found: $EXEC_PATH" >&2
  exit 2
fi

EXEC_BASENAME=$(basename "$EXEC_PATH")
APP_NAME=$(basename "$OUT_APP_PATH" .app)

# Versioning: allow callers to override the app version and build via env vars
# Default to the next release version
APP_VERSION="${APP_VERSION:-0.0.3}"
APP_BUILD="${APP_BUILD:-0}"

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
  <key>CFBundleDisplayName</key>
  <string>$EXEC_BASENAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$EXEC_BASENAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD}</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
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

# Normalize permissions/attributes so the resulting .app can be moved/installed without Finder permission errors
# - remove extended attributes (quarantine)
# - clear immutable/locked flags
# - ensure user read/write/execute where appropriate
if [ -d "$OUT_APP_PATH" ]; then
  echo "Normalizing permissions and attributes for: $OUT_APP_PATH"
  # Remove extended attributes recursively
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$OUT_APP_PATH" || true
    # Some attributes (e.g. com.apple.provenance) may persist; remove explicitly
    xattr -dr com.apple.provenance "$OUT_APP_PATH" || true
  fi
  # Clear immutable flags
  if command -v chflags >/dev/null 2>&1; then
    chflags -R nouchg "$OUT_APP_PATH" || true
  fi
  # Ensure owner can read/write/execute as appropriate (avoid chown in CI)
  chmod -R u+rwX "$OUT_APP_PATH" || true
fi

echo "App bundle created: $OUT_APP_PATH"

# Signing configuration: can be overridden via environment variables
# By default, perform ad-hoc signing so local builds work
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS="${ENTITLEMENTS:-}"
SIGN_OPTIONS="${SIGN_OPTIONS:-}"

# Sign the original output if signing is enabled
if [ -n "${SIGN_IDENTITY}" ]; then
  echo "Signing $OUT_APP_PATH with: ${SIGN_IDENTITY}"
  if command -v codesign >/dev/null 2>&1; then
    read -r -a _sign_opts <<< "${SIGN_OPTIONS}"
    codesign_cmd=(/usr/bin/codesign --force --deep)
    if [ ${#_sign_opts[@]} -gt 0 ]; then
      codesign_cmd+=("${_sign_opts[@]}")
    fi
    if [ -n "${ENTITLEMENTS}" ]; then
      codesign_cmd+=(--entitlements "${ENTITLEMENTS}")
    fi
    codesign_cmd+=(--sign "${SIGN_IDENTITY}" "${OUT_APP_PATH}")
    
    "${codesign_cmd[@]}"
    echo "Signed: $OUT_APP_PATH"
  else
    echo "Warning: codesign not available; skipping signing"
  fi
fi

# If the output is created inside ./artifacts and has an arch suffix (e.g. Ticklet-<arch>.app),
# create a canonical ./artifacts/Ticklet.app copy so install instructions can be run reliably.
OUT_DIR=$(dirname "$OUT_APP_PATH")
OUT_BASE=$(basename "$OUT_APP_PATH")
# Support two artifact layouts:
#  - per-arch file: ./artifacts/Ticklet-<arch>.app
#  - per-arch dir:  ./artifacts/<arch>/Ticklet.app
# Determine the artifacts directory (parent 'artifacts') when given a per-arch dir
ARTIFACTS_DIR="$OUT_DIR"
if [ "$OUT_BASE" = "Ticklet.app" ] && [ "$(basename "$OUT_DIR")" != "artifacts" ]; then
  ARTIFACTS_DIR="$(dirname "$OUT_DIR")"
fi
# If the output looks like an arch-specific artifact or is inside an artifacts/<arch> folder,
# create/update a canonical ./artifacts/Ticklet.app copy so install instructions can be run reliably.
if ( echo "$OUT_BASE" | grep -qE '^Ticklet-[a-zA-Z0-9_]+\.app$' ) || ( echo "$OUT_APP_PATH" | grep -qE '/artifacts/[^/]+/Ticklet.app$' ) || [ "$(basename "$ARTIFACTS_DIR")" = "artifacts" ]; then
  CANONICAL="$ARTIFACTS_DIR/Ticklet.app"
  echo "Creating canonical artifact: $CANONICAL"
  rm -rf "$CANONICAL" || true
  cp -R "$OUT_APP_PATH" "$CANONICAL"
  # Normalize the canonical copy as well
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$CANONICAL" || true
    xattr -dr com.apple.provenance "$CANONICAL" || true
  fi
  if command -v chflags >/dev/null 2>&1; then
    chflags -R nouchg "$CANONICAL" || true
  fi
  chmod -R u+rwX "$CANONICAL" || true
  echo "Canonical artifact ready: $CANONICAL"

  if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "Signing canonical artifact with: ${SIGN_IDENTITY}"
    if command -v codesign >/dev/null 2>&1; then
      # compose codesign command supporting optional SIGN_OPTIONS and ENTITLEMENTS
      read -r -a _sign_opts <<< "${SIGN_OPTIONS}"
      codesign_cmd=(/usr/bin/codesign --force --deep)
      if [ ${#_sign_opts[@]} -gt 0 ]; then
        codesign_cmd+=("${_sign_opts[@]}")
      fi
      if [ -n "${ENTITLEMENTS}" ]; then
        codesign_cmd+=(--entitlements "${ENTITLEMENTS}")
      fi
      codesign_cmd+=(--sign "${SIGN_IDENTITY}" "${CANONICAL}")

      # Execute codesign (fail the script if signing fails)
      "${codesign_cmd[@]}"
      echo "codesign details for ${CANONICAL}:" && /usr/bin/codesign -dvvv "${CANONICAL}" 2>&1
      if command -v spctl >/dev/null 2>&1; then
        echo "spctl assessment for ${CANONICAL}:" && spctl --assess --type execute --verbose "${CANONICAL}" 2>&1 || true
      fi
    else
      echo "codesign not available on PATH; skipping signing"
    fi
  fi
fi

# Optional verification: unzip the staged copy and attempt a copy to a temp install location
# to detect whether Finder/OS would skip items when users move the app.
# Enable by setting VERIFY_INSTALL=1 in the environment when invoking this script.
if [ "${VERIFY_INSTALL:-0}" = "1" ]; then
  echo "VERIFY_INSTALL set: validating that the packaged .app can be copied without skipping items"
  TMP_DIR=$(mktemp -d)
  STAGE_DIR="$TMP_DIR/staging"
  INSTALL_DIR="$TMP_DIR/install"
  mkdir -p "$STAGE_DIR" "$INSTALL_DIR"

  # make a normalized staging copy and zip it
  cp -R "$OUT_APP_PATH" "$STAGE_DIR/Ticklet.app"
  ZIP_PATH="$TMP_DIR/test.zip"
  ditto -c -k --sequesterRsrc --keepParent "$STAGE_DIR/Ticklet.app" "$ZIP_PATH"

  echo "Unpacking test zip to: $TMP_DIR/unpack"
  mkdir -p "$TMP_DIR/unpack"
  unzip -qq -d "$TMP_DIR/unpack" "$ZIP_PATH"

  echo "Attempting to copy unpacked app to simulated install dir: $INSTALL_DIR"
  set +e
  cp -R "$TMP_DIR/unpack/Ticklet.app" "$INSTALL_DIR/" 2>"$TMP_DIR/cp.err"
  CP_EXIT=$?
  set -e

  if [ $CP_EXIT -ne 0 ]; then
    echo "ERROR: simulated copy failed with exit code $CP_EXIT"
    echo "cp stderr:" && sed -n '1,200p' "$TMP_DIR/cp.err"
    echo "Listing source attributes for diagnostic:"
    ls -laO "$TMP_DIR/unpack/Ticklet.app" || true
    xattr -lr "$TMP_DIR/unpack/Ticklet.app" || true
    echo "Listing target dir after attempted copy:"
    ls -laR "$INSTALL_DIR" || true
    echo "Packaging verification failed: the zip may produce a .app that Finder or users cannot move cleanly."
    echo "You can reproduce locally by setting VERIFY_INSTALL=1 when running the script."
  else
    echo "Packaging verification succeeded: simulated install copy completed without error."
  fi

  rm -rf "$TMP_DIR"
fi

cat <<USAGE
Next steps:
 1) Double-click the app ($OUT_APP_PATH) to register it with Launch Services.
 2) Open System Settings → Privacy & Security → Accessibility and add/enable $OUT_APP_PATH.
 3) Quit the app if it's running and then run it again (or run from Finder).

If you are debugging via Xcode, consider granting Accessibility to Xcode instead of the standalone binary.
USAGE
