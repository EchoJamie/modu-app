#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/build/MoDu.app"
CONTENTS_DIR="$APP_DIR/Contents"
ICON_SOURCE="$PROJECT_DIR/Config/AppIcon-1024.png"
ICONSET_DIR="$PROJECT_DIR/build/AppIcon.iconset"
RESOURCE_BUNDLE_SOURCE="$PROJECT_DIR/.build/release/MoDu_MoDu.bundle"

swift build --package-path "$PROJECT_DIR" -c release

if [[ "$APP_DIR" != "$PROJECT_DIR/build/MoDu.app" ]]; then
  print -u2 "拒绝清理非预期构建目录：$APP_DIR"
  exit 1
fi

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
/bin/cp "$PROJECT_DIR/.build/release/MoDu" "$CONTENTS_DIR/MacOS/MoDu"
/bin/cp "$PROJECT_DIR/Config/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ ! -d "$RESOURCE_BUNDLE_SOURCE" ]]; then
  print -u2 "缺少 SwiftPM 资源包：$RESOURCE_BUNDLE_SOURCE"
  exit 1
fi
/usr/bin/ditto "$RESOURCE_BUNDLE_SOURCE" "$CONTENTS_DIR/Resources/MoDu_MoDu.bundle"
for localization in en zh-Hans; do
  /usr/bin/ditto \
    "$PROJECT_DIR/Sources/MoDu/Resources/$localization.lproj" \
    "$CONTENTS_DIR/Resources/$localization.lproj"
done
/usr/bin/printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if [[ ! -f "$ICON_SOURCE" ]]; then
  print -u2 "缺少应用图标源文件：$ICON_SOURCE"
  exit 1
fi
/bin/rm -rf "$ICONSET_DIR"
/bin/mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  /usr/bin/sips -z "$double_size" "$double_size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$CONTENTS_DIR/Resources/AppIcon.icns"
/bin/rm -rf "$ICONSET_DIR"

/usr/bin/codesign \
  --force \
  --sign - \
  --entitlements "$PROJECT_DIR/Config/MoDu.entitlements" \
  "$APP_DIR"

"$CONTENTS_DIR/MacOS/MoDu" -AppleLanguages '(en)' --webview-self-check
"$CONTENTS_DIR/MacOS/MoDu" -AppleLanguages '(zh-Hans)' --webview-self-check

print "已构建：$APP_DIR"
