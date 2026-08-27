#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/build/MoDu.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Config/Info.plist")"
DMG_PATH="$PROJECT_DIR/build/MoDu-$APP_VERSION.dmg"
STAGING_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/modu-dmg.XXXXXX")"

cleanup() {
  /bin/rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

"$SCRIPT_DIR/build_app.sh"
/usr/bin/ditto "$APP_DIR" "$STAGING_DIR/MoDu.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/bin/rm -f "$DMG_PATH"
/usr/bin/hdiutil create \
  -volname "MoDu" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

dmg_sha="$(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{print $1}')"
print "dmg_sha256=$dmg_sha" >> "$PROJECT_DIR/build/release-manifest.txt"
print "dmg_path=build/${DMG_PATH:t}" >> "$PROJECT_DIR/build/release-manifest.txt"

print "已生成：$DMG_PATH"
