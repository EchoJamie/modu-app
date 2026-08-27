#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${2:-$PROJECT_DIR/build/MoDu.app}"
MODE="${1:-prepare}"
MANIFEST="$PROJECT_DIR/build/release-manifest.txt"
APP_MANIFEST="$APP_DIR/Contents/Resources/BuildManifest.txt"
FILE_DIGESTS="$PROJECT_DIR/build/app-files.sha256"
SOURCE_PATCH="$PROJECT_DIR/build/source-state.patch"
UNTRACKED_LIST="$PROJECT_DIR/build/source-state-untracked.txt"
UNTRACKED_ARCHIVE="$PROJECT_DIR/build/source-state-untracked.tar"

if [[ "$APP_DIR" != "$PROJECT_DIR/build/MoDu.app" || ! -d "$APP_DIR" ]]; then
  print -u2 "拒绝为非预期应用目录生成追溯信息：$APP_DIR"
  exit 1
fi

dirty_state="$(/usr/bin/git -C "$PROJECT_DIR" status --porcelain --untracked-files=all)"
if [[ -n "$dirty_state" && "${ALLOW_DIRTY_BUILD:-0}" != "1" ]]; then
  print -u2 "追溯清单拒绝 dirty 工作树；仅开发验证可显式设置 ALLOW_DIRTY_BUILD=1。"
  exit 1
fi
current_source_fingerprint="$("$SCRIPT_DIR/source_state_fingerprint.sh")"
current_dependency_fingerprint="$("$SCRIPT_DIR/dependency_state_fingerprint.sh")"

if [[ "$MODE" == "prepare" ]]; then
  /usr/bin/git -C "$PROJECT_DIR" diff --binary --no-ext-diff HEAD > "$SOURCE_PATCH"
  /usr/bin/git -C "$PROJECT_DIR" ls-files --others --exclude-standard |
    LC_ALL=C /usr/bin/sort > "$UNTRACKED_LIST"
  (
    cd "$PROJECT_DIR"
    /usr/bin/tar -cf "$UNTRACKED_ARCHIVE" -T "$UNTRACKED_LIST"
  )

  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Config/Info.plist")"
  build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PROJECT_DIR/Config/Info.plist")"
  commit="$(/usr/bin/git -C "$PROJECT_DIR" rev-parse HEAD)"
  patch_sha="$(/usr/bin/shasum -a 256 "$SOURCE_PATCH" | /usr/bin/awk '{print $1}')"
  untracked_sha="$(/usr/bin/shasum -a 256 "$UNTRACKED_ARCHIVE" | /usr/bin/awk '{print $1}')"
  package_sha="$(/usr/bin/shasum -a 256 "$PROJECT_DIR/Package.resolved" | /usr/bin/awk '{print $1}')"
  swift_version="$(swift --version | /usr/bin/head -n 1)"
  sdk_version="$(/usr/bin/xcrun --sdk macosx --show-sdk-version)"
  architecture="$(/usr/bin/uname -m)"
  source_date_epoch="${SOURCE_DATE_EPOCH:-$(/usr/bin/git -C "$PROJECT_DIR" show -s --format=%ct HEAD)}"
  dirty_build=false
  if [[ -s "$SOURCE_PATCH" || -s "$UNTRACKED_LIST" ]]; then
    dirty_build=true
  fi

  /bin/mkdir -p "${APP_MANIFEST:h}"
  {
    print "format=1"
    print "version=$version"
    print "build=$build_number"
    print "git_commit=$commit"
    print "dirty_build=$dirty_build"
    print "source_state_sha256=$current_source_fingerprint"
    print "dependency_state_sha256=$current_dependency_fingerprint"
    print "source_patch_sha256=$patch_sha"
    print "source_patch=build/source-state.patch"
    print "untracked_archive_sha256=$untracked_sha"
    print "untracked_archive=build/source-state-untracked.tar"
    print "package_resolved_sha256=$package_sha"
    print "source_date_epoch=$source_date_epoch"
    print "architecture=$architecture"
    print "macos_sdk=$sdk_version"
    print "swift=$swift_version"
  } > "$MANIFEST"
  /bin/cp "$MANIFEST" "$APP_MANIFEST"
  exit 0
fi

if [[ "$MODE" != "finalize" || ! -f "$MANIFEST" ]]; then
  print -u2 "未知追溯阶段或缺少预备清单：$MODE"
  exit 1
fi

prepared_source_fingerprint="$(
  /usr/bin/grep -E '^source_state_sha256=' "$MANIFEST" |
    /usr/bin/tail -n 1 |
    /usr/bin/sed 's/^source_state_sha256=//'
)"
prepared_dependency_fingerprint="$(
  /usr/bin/grep -E '^dependency_state_sha256=' "$MANIFEST" |
    /usr/bin/tail -n 1 |
    /usr/bin/sed 's/^dependency_state_sha256=//'
)"
if [[ -z "$prepared_source_fingerprint" ||
      "$prepared_source_fingerprint" != "$current_source_fingerprint" ||
      -z "$prepared_dependency_fingerprint" ||
      "$prepared_dependency_fingerprint" != "$current_dependency_fingerprint" ]]; then
  print -u2 "源码状态与预备追溯清单不一致；拒绝完成交付。"
  exit 1
fi

(
  cd "$APP_DIR"
  find . -type f -print | LC_ALL=C /usr/bin/sort | while IFS= read -r path; do
    digest="$(/usr/bin/shasum -a 256 "$path" | /usr/bin/awk '{print $1}')"
    print "$digest  $path"
  done
) > "$FILE_DIGESTS"
app_tree_sha="$(/usr/bin/shasum -a 256 "$FILE_DIGESTS" | /usr/bin/awk '{print $1}')"
print "app_file_manifest_sha256=$app_tree_sha" >> "$MANIFEST"
print "app_file_manifest=build/app-files.sha256" >> "$MANIFEST"
