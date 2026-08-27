#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
PLIST="$PROJECT_DIR/Config/Info.plist"
CHANGELOG="$PROJECT_DIR/changelog.md"
RELEASE_BASELINE="$PROJECT_DIR/Config/release-baseline.json"

if [[ -n "$(/usr/bin/git -C "$PROJECT_DIR" status --porcelain --untracked-files=all)" &&
      "${ALLOW_DIRTY_BUILD:-0}" != "1" ]]; then
  print -u2 "正式交付拒绝 dirty 工作树；请先提交全部输入，或仅为开发验证显式设置 ALLOW_DIRTY_BUILD=1。"
  exit 1
fi

"$SCRIPT_DIR/verify_third_party.sh"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "应用版本号不是 x.y.z：$version"
  exit 1
fi
if [[ ! "$build_number" =~ '^[0-9]+$' ]]; then
  print -u2 "构建号不是正整数：$build_number"
  exit 1
fi

latest_changelog_version="$(
  /usr/bin/grep -E '^## [0-9]+\.[0-9]+\.[0-9]+ — ' "$CHANGELOG" | /usr/bin/tail -n 1 |
    /usr/bin/sed -E 's/^## ([0-9]+\.[0-9]+\.[0-9]+) — .*/\1/'
)"
if [[ "$latest_changelog_version" != "$version" ]]; then
  print -u2 "Info.plist 版本 $version 与 changelog 最新版本 $latest_changelog_version 不一致"
  exit 1
fi

if [[ ! -s "$RELEASE_BASELINE" ]]; then
  print -u2 "缺少上一正式交付基线：$RELEASE_BASELINE"
  exit 1
fi
/usr/bin/plutil -convert json -o /dev/null "$RELEASE_BASELINE"
baseline_version="$(/usr/bin/plutil -extract version raw -o - "$RELEASE_BASELINE")"
baseline_build="$(/usr/bin/plutil -extract build raw -o - "$RELEASE_BASELINE")"
baseline_commit="$(/usr/bin/plutil -extract commit raw -o - "$RELEASE_BASELINE")"
if [[ ! "$baseline_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ||
      ! "$baseline_build" =~ '^[0-9]+$' ||
      ! "$baseline_commit" =~ '^[0-9a-f]{40}$' ]]; then
  print -u2 "上一交付基线格式无效。"
  exit 1
fi
if ! /usr/bin/git -C "$PROJECT_DIR" merge-base --is-ancestor "$baseline_commit" HEAD; then
  print -u2 "上一交付提交不是当前 HEAD 的祖先：$baseline_commit"
  exit 1
fi

baseline_plist="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/modu-baseline-info.XXXXXX")"
trap '/bin/rm -f "$baseline_plist"' EXIT
/usr/bin/git -C "$PROJECT_DIR" show "$baseline_commit:Config/Info.plist" > "$baseline_plist"
recorded_baseline_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$baseline_plist")"
recorded_baseline_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$baseline_plist")"
if [[ "$recorded_baseline_version" != "$baseline_version" ||
      "$recorded_baseline_build" != "$baseline_build" ]]; then
  print -u2 "上一交付基线与其 Git 提交中的版本元数据不一致。"
  exit 1
fi

current_major="${version%%.*}"
current_remainder="${version#*.}"
current_minor="${current_remainder%%.*}"
current_patch="${current_remainder#*.}"
baseline_major="${baseline_version%%.*}"
baseline_remainder="${baseline_version#*.}"
baseline_minor="${baseline_remainder%%.*}"
baseline_patch="${baseline_remainder#*.}"
if (( current_major < baseline_major ||
      (current_major == baseline_major && current_minor < baseline_minor) ||
      (current_major == baseline_major && current_minor == baseline_minor && current_patch <= baseline_patch) )); then
  print -u2 "版本号必须高于上一交付 $baseline_version：当前 $version"
  exit 1
fi
if (( build_number <= baseline_build )); then
  print -u2 "构建号必须高于上一交付 $baseline_build：当前 $build_number"
  exit 1
fi

print "版本与发布元数据校验通过：$version ($build_number)，上一交付 $baseline_version ($baseline_build)。"
