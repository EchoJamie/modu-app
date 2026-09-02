#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BUILD_FLAVOR="${MODU_BUILD_FLAVOR:-preview}"
PREVIEW_APP_DIR="$PROJECT_DIR/build/MoDu Preview.app"
FORMAL_APP_DIR="$PROJECT_DIR/build/.formal/MoDu.app"
LEGACY_APP_DIR="$PROJECT_DIR/build/MoDu.app"
case "$BUILD_FLAVOR" in
  preview)
    APP_DIR="$PREVIEW_APP_DIR"
    EXPECTED_BUNDLE_IDENTIFIER="com.local.modu.preview"
    EXPECTED_ENGLISH_NAME="MoDu Preview"
    EXPECTED_CHINESE_NAME="墨读预览版"
    ;;
  formal)
    APP_DIR="$FORMAL_APP_DIR"
    EXPECTED_BUNDLE_IDENTIFIER="com.local.modu"
    EXPECTED_ENGLISH_NAME="MoDu"
    EXPECTED_CHINESE_NAME="墨读"
    ;;
  *)
    print -u2 "未知应用构建类型：$BUILD_FLAVOR"
    exit 1
    ;;
esac
CONTENTS_DIR="$APP_DIR/Contents"
ICON_SOURCE="$PROJECT_DIR/Config/AppIcon-1024.png"
ICONSET_DIR="$PROJECT_DIR/build/AppIcon.iconset"
RESOURCE_BUNDLE_SOURCE="$PROJECT_DIR/.build/release/MoDu_MoDu.bundle"
PREVIEW_LOCALIZATION_SOURCE="$PROJECT_DIR/Config/Preview"
CLI_SOURCE="$PROJECT_DIR/Support/CLI/modu"
CLI_DIR="$CONTENTS_DIR/Resources/CLI"
CLI_INSTALLER_SOURCE="$PROJECT_DIR/.build/release/MoDuCLIInstaller"
CLI_INSTALLER_INFO="$PROJECT_DIR/Config/MoDuCLIInstaller-Info.plist"
CLI_INSTALLER_HELPERS_DIR="$CONTENTS_DIR/Helpers"
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

if [[ "$APP_DIR" != "$PREVIEW_APP_DIR" && "$APP_DIR" != "$FORMAL_APP_DIR" ]]; then
  print -u2 "拒绝清理非预期构建目录：$APP_DIR"
  exit 1
fi

/bin/rm -rf "$APP_DIR"
if [[ -d "$LEGACY_APP_DIR" ]]; then
  /bin/rm -rf "$LEGACY_APP_DIR"
fi
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
if [[ "$BUILD_FLAVOR" == "preview" ]]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName MoDu Preview' "$CONTENTS_DIR/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName MoDu Preview' "$CONTENTS_DIR/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.local.modu.preview' "$CONTENTS_DIR/Info.plist"
  for localization in en zh-Hans; do
    /bin/cp \
      "$PREVIEW_LOCALIZATION_SOURCE/$localization.lproj/InfoPlist.strings" \
      "$CONTENTS_DIR/Resources/$localization.lproj/InfoPlist.strings"
  done
fi

if [[ ! -f "$CLI_SOURCE" ]]; then
  print -u2 "缺少命令行启动器：$CLI_SOURCE"
  exit 1
fi
/bin/mkdir -p "$CLI_DIR"
/bin/cp "$CLI_SOURCE" "$CLI_DIR/modu"
/bin/chmod 755 "$CLI_DIR/modu"
/bin/zsh -n "$CLI_DIR/modu"

if [[ ! -x "$CLI_INSTALLER_SOURCE" || ! -f "$CLI_INSTALLER_INFO" ]]; then
  print -u2 "缺少命令行工具系统授权助手。"
  exit 1
fi

package_cli_installer() {
  local operation="$1"
  local bundle_name="$2"
  local identifier_suffix="$3"
  local helper_app="$CLI_INSTALLER_HELPERS_DIR/$bundle_name"
  local helper_contents="$helper_app/Contents"

  /bin/mkdir -p \
    "$helper_contents/MacOS" \
    "$helper_contents/Resources/en.lproj" \
    "$helper_contents/Resources/zh-Hans.lproj"
  /bin/cp "$CLI_INSTALLER_SOURCE" "$helper_contents/MacOS/MoDuCLIInstaller"
  /bin/chmod 755 "$helper_contents/MacOS/MoDuCLIInstaller"
  /bin/cp "$CLI_INSTALLER_INFO" "$helper_contents/Info.plist"
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier $EXPECTED_BUNDLE_IDENTIFIER.$identifier_suffix" \
    "$helper_contents/Info.plist"
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleDisplayName $EXPECTED_ENGLISH_NAME" \
    "$helper_contents/Info.plist"
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleName $EXPECTED_ENGLISH_NAME" \
    "$helper_contents/Info.plist"
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS_DIR/Info.plist")" \
    "$helper_contents/Info.plist"
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CONTENTS_DIR/Info.plist")" \
    "$helper_contents/Info.plist"
  /usr/libexec/PlistBuddy \
    -c "Set :MoDuCLIInstallerOperation $operation" \
    "$helper_contents/Info.plist"
  local actual_helper_identifier
  local actual_helper_operation
  actual_helper_identifier="$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$helper_contents/Info.plist"
  )"
  actual_helper_operation="$(
    /usr/libexec/PlistBuddy -c 'Print :MoDuCLIInstallerOperation' "$helper_contents/Info.plist"
  )"
  if [[ "$actual_helper_identifier" != "$EXPECTED_BUNDLE_IDENTIFIER.$identifier_suffix" ||
        "$actual_helper_operation" != "$operation" ]]; then
    print -u2 "系统授权助手职责校验失败：$bundle_name"
    exit 1
  fi
  for localization in en zh-Hans; do
    /bin/cp \
      "$CONTENTS_DIR/Resources/$localization.lproj/InfoPlist.strings" \
      "$helper_contents/Resources/$localization.lproj/InfoPlist.strings"
  done
  /usr/bin/printf 'APPL????' > "$helper_contents/PkgInfo"

  /usr/bin/codesign --force --sign - "$helper_app"
  local helper_entitlements
  helper_entitlements="$(/usr/bin/codesign -d --entitlements - "$helper_app" 2>/dev/null || true)"
  if [[ "$helper_entitlements" == *"com.apple.security.app-sandbox"* ]]; then
    print -u2 "系统授权助手不得继承应用沙盒：$bundle_name"
    exit 1
  fi
  /usr/bin/codesign --verify --strict "$helper_app"
}

package_cli_installer install "MoDuCLIInstall.app" "cli-install"
package_cli_installer uninstall "MoDuCLIUninstall.app" "cli-uninstall"

actual_bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS_DIR/Info.plist")"
actual_english_name="$(
  /usr/bin/plutil -extract CFBundleDisplayName raw -o - \
    "$CONTENTS_DIR/Resources/en.lproj/InfoPlist.strings"
)"
actual_chinese_name="$(
  /usr/bin/plutil -extract CFBundleDisplayName raw -o - \
    "$CONTENTS_DIR/Resources/zh-Hans.lproj/InfoPlist.strings"
)"
if [[ "$actual_bundle_identifier" != "$EXPECTED_BUNDLE_IDENTIFIER" ||
      "$actual_english_name" != "$EXPECTED_ENGLISH_NAME" ||
      "$actual_chinese_name" != "$EXPECTED_CHINESE_NAME" ]]; then
  print -u2 "应用构建身份校验失败：$BUILD_FLAVOR"
  exit 1
fi
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
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
main_entitlements="$(/usr/bin/codesign -d --entitlements - "$APP_DIR" 2>/dev/null || true)"
if [[ "$main_entitlements" != *"com.apple.security.app-sandbox"* ]]; then
  print -u2 "主应用缺少预期的沙盒权限。"
  exit 1
fi

"$CONTENTS_DIR/MacOS/MoDu" -AppleLanguages '(en)' --webview-self-check
"$CONTENTS_DIR/MacOS/MoDu" -AppleLanguages '(zh-Hans)' --webview-self-check
verify_source_state
"$SCRIPT_DIR/write_release_manifest.sh" finalize "$APP_DIR"

print "已构建：$APP_DIR"
