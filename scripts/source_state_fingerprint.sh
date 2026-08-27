#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
STATE_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/modu-source-state.XXXXXX")"

cleanup() {
  /bin/rm -f "$STATE_FILE"
}
trap cleanup EXIT

{
  /usr/bin/git -C "$PROJECT_DIR" rev-parse HEAD
  /usr/bin/git -C "$PROJECT_DIR" diff --binary --no-ext-diff HEAD
  /usr/bin/git -C "$PROJECT_DIR" ls-files --others --exclude-standard |
    LC_ALL=C /usr/bin/sort |
    while IFS= read -r relative_path; do
      [[ -n "$relative_path" ]] || continue
      absolute_path="$PROJECT_DIR/$relative_path"
      print -r -- "untracked=$relative_path"
      /usr/bin/stat -f 'mode=%p' "$absolute_path"
      if [[ -L "$absolute_path" ]]; then
        print -r -- "target=$(/usr/bin/readlink "$absolute_path")"
      elif [[ -f "$absolute_path" ]]; then
        /usr/bin/shasum -a 256 "$absolute_path"
      else
        print -r -- "node=non-regular"
      fi
    done
} > "$STATE_FILE"

/usr/bin/shasum -a 256 "$STATE_FILE" | /usr/bin/awk '{print $1}'
