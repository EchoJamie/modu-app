#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/build/墨读.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Config/Info.plist")"
DMG_PATH="$PROJECT_DIR/build/墨读-$APP_VERSION.dmg"
STAGING_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/modu-dmg.XXXXXX")"

cleanup() {
  /bin/rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

"$SCRIPT_DIR/build_app.sh"
/usr/bin/ditto "$APP_DIR" "$STAGING_DIR/墨读.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/bin/rm -f "$DMG_PATH"
/usr/bin/hdiutil create \
  -volname "墨读" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

print "已生成：$DMG_PATH"
