#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/build/MoDu.app"
CONTENTS_DIR="$APP_DIR/Contents"
ICON_SOURCE="$PROJECT_DIR/Config/AppIcon-1024.png"
ICONSET_DIR="$PROJECT_DIR/build/AppIcon.iconset"
RESOURCE_BUNDLE_SOURCE="$PROJECT_DIR/.build/release/MoDu_MoDu.bundle"
LICENSE_DIR="$CONTENTS_DIR/Resources/ThirdPartyLicenses"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(/usr/bin/git -C "$PROJECT_DIR" show -s --format=%ct HEAD)}"

if [[ -n "$(/usr/bin/git -C "$PROJECT_DIR" status --porcelain --untracked-files=all)" &&
      "${ALLOW_DIRTY_BUILD:-0}" != "1" ]]; then
  print -u2 "正式交付拒绝 dirty 工作树；依赖解析前终止。"
  exit 1
fi

swift package --package-path "$PROJECT_DIR" resolve

"$SCRIPT_DIR/verify_release.sh"
initial_source_fingerprint="$("$SCRIPT_DIR/source_state_fingerprint.sh")"
initial_dependency_fingerprint="$("$SCRIPT_DIR/dependency_state_fingerprint.sh")"

verify_source_state() {
  current_source_fingerprint="$("$SCRIPT_DIR/source_state_fingerprint.sh")"
  if [[ "$current_source_fingerprint" != "$initial_source_fingerprint" ]]; then
    print -u2 "构建期间源码状态发生变化；拒绝生成不可追溯交付物。"
    exit 1
  fi
  current_dependency_fingerprint="$("$SCRIPT_DIR/dependency_state_fingerprint.sh")"
  if [[ "$current_dependency_fingerprint" != "$initial_dependency_fingerprint" ]]; then
    print -u2 "构建期间 SwiftPM 依赖状态发生变化；拒绝生成不可追溯交付物。"
    exit 1
  fi
  "$SCRIPT_DIR/verify_release.sh"
}

swift test --package-path "$PROJECT_DIR" -Xswiftc -warnings-as-errors
swift build --package-path "$PROJECT_DIR" -c release -Xswiftc -warnings-as-errors
verify_source_state

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
/bin/mkdir -p "$LICENSE_DIR"
/bin/cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$CONTENTS_DIR/Resources/THIRD_PARTY_NOTICES.md"
"$SCRIPT_DIR/copy_third_party_licenses.sh" "$LICENSE_DIR"
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

"$SCRIPT_DIR/write_release_manifest.sh" prepare "$APP_DIR"

/usr/bin/codesign \
  --force \
  --sign - \
  --entitlements "$PROJECT_DIR/Config/MoDu.entitlements" \
  "$APP_DIR"

"$CONTENTS_DIR/MacOS/MoDu" -AppleLanguages '(en)' --webview-self-check
"$CONTENTS_DIR/MacOS/MoDu" -AppleLanguages '(zh-Hans)' --webview-self-check
verify_source_state
"$SCRIPT_DIR/write_release_manifest.sh" finalize "$APP_DIR"

print "已构建：$APP_DIR"
