#!/usr/bin/env bash
# Builds a Release KRETEN.app and packages it as a drag-and-drop DMG installer
# (app icon + /Applications shortcut) in dist/.
#
# Usage: scripts/build-dmg.sh [options]
#   -o, --output <dir>   where to put the .dmg (default: dist/)
#   -a, --arch <archs>   "universal" (default), "arm64" or "x86_64"
#   -c, --clean          wipe build/ before building
#       --no-layout      skip the Finder window styling (useful on headless/CI machines)
#   -h, --help
#
# Signing (optional; without it the app is ad-hoc signed and runs on this Mac,
# while other Macs need right-click → Open the first time):
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"   sign app + DMG
#   NOTARY_PROFILE=<keychain profile>                          notarize + staple the DMG
#     (create the profile once with `xcrun notarytool store-credentials`)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="KRETEN"
VOLUME_NAME="KRETÉN"
BUILD_DIR="$ROOT/build"
OUT_DIR="$ROOT/dist"
ARCH="universal"
CLEAN=0
LAYOUT=1

die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) [[ $# -ge 2 ]] || die "$1 needs a directory"; OUT_DIR="$2"; shift 2 ;;
    -a|--arch) [[ $# -ge 2 ]] || die "$1 needs a value"; ARCH="$2"; shift 2 ;;
    -c|--clean) CLEAN=1; shift ;;
    --no-layout) LAYOUT=0; shift ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

case "$ARCH" in
  universal) ARCHS="arm64 x86_64" ;;
  arm64|x86_64) ARCHS="$ARCH" ;;
  *) die "--arch must be universal, arm64 or x86_64" ;;
esac

[[ "$(uname -s)" == "Darwin" ]] || die "this script needs macOS"
command -v xcodebuild >/dev/null || die "xcodebuild not found; install Xcode 26+"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# ---------------------------------------------------------------- build app
[[ $CLEAN -eq 1 ]] && { step "Cleaning $BUILD_DIR"; rm -rf "$BUILD_DIR"; }

step "Building $APP_NAME.app (Release, $ARCHS)"
sign_args=()
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  sign_args=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp")
fi
log="$BUILD_DIR/xcodebuild.log"
mkdir -p "$BUILD_DIR"
if ! xcodebuild \
    -project "$ROOT/Kreten.xcodeproj" \
    -scheme Kreten \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
    ${sign_args[@]+"${sign_args[@]}"} \
    build >"$log" 2>&1; then
  grep -E "error:" "$log" | sort -u >&2 || true
  die "xcodebuild failed; full log: $log"
fi
grep -E "warning:" "$log" | sort -u || true

APP="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || die "build succeeded but $APP is missing"
codesign --verify --deep --strict "$APP" || die "code signature of $APP is invalid"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"), version $VERSION)"

# --------------------------------------------------------------- stage DMG
step "Staging disk image contents"
STAGE="$BUILD_DIR/dmg-stage"
RW_DMG="$BUILD_DIR/$APP_NAME-rw.dmg"
rm -rf "$STAGE" "$RW_DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

# A mounted volume with the same name would make Finder address the wrong window.
if [[ -d "/Volumes/$VOLUME_NAME" ]]; then
  hdiutil detach "/Volumes/$VOLUME_NAME" -force -quiet || die "/Volumes/$VOLUME_NAME is in use; eject it first"
fi

size_mb=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$STAGE" \
  -fs HFS+ -format UDRW -size "${size_mb}m" "$RW_DMG"

MOUNT_DIR=""
detach() {
  [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]] || return 0
  hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet || true
  MOUNT_DIR=""
}
trap detach EXIT

MOUNT_DIR="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -nobrowse \
  | awk -F'\t' '/\/Volumes\// { print $NF; exit }')"
[[ -d "$MOUNT_DIR" ]] || die "could not mount $RW_DMG"

# --------------------------------------------------- Finder window layout
if [[ $LAYOUT -eq 1 ]]; then
  step "Arranging the installer window"
  # Volume must be visible to Finder for scripting, so re-attach without -nobrowse.
  detach
  MOUNT_DIR="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen \
    | awk -F'\t' '/\/Volumes\// { print $NF; exit }')"
  disk_name="$(basename "$MOUNT_DIR")"
  if ! osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
  tell disk "$disk_name"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 480}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set position of item "$APP_NAME.app" of container window to {140, 160}
    set position of item "Applications" of container window to {400, 160}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
  then
    echo "warning: Finder styling failed (allow Terminal to control Finder in" >&2
    echo "         System Settings → Privacy & Security → Automation); the DMG still works." >&2
  fi
  rm -rf "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Trashes" 2>/dev/null || true
fi

sync
detach
trap - EXIT

# ---------------------------------------------------------- compress DMG
step "Compressing $DMG"
rm -f "$DMG"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$RW_DMG" "$STAGE"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  step "Signing DMG"
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ -n "${SIGN_IDENTITY:-}" ]] || die "NOTARY_PROFILE needs SIGN_IDENTITY (a Developer ID certificate)"
  step "Notarizing DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

hdiutil verify -quiet "$DMG"
printf '\n✓ %s (%s)\n' "$DMG" "$(du -h "$DMG" | cut -f1 | tr -d ' ')"
