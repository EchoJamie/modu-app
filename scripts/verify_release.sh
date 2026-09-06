#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
PLIST="$PROJECT_DIR/Config/Info.plist"
CHANGELOG="$PROJECT_DIR/changelog.md"

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

print "版本与发布元数据校验通过：$version ($build_number)。"
