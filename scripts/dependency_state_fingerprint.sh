#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
MANIFEST="$PROJECT_DIR/Config/third-party-components.json"
STATE_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/modu-dependency-state.XXXXXX")"

cleanup() {
  /bin/rm -f "$STATE_FILE"
}
trap cleanup EXIT

component_index=0
while identity="$(/usr/bin/plutil -extract "components.$component_index.identity" raw -o - "$MANIFEST" 2>/dev/null)"; do
  kind="$(/usr/bin/plutil -extract "components.$component_index.kind" raw -o - "$MANIFEST")"
  if [[ "$kind" == "swiftpm" ]]; then
    checkout_path="$(/usr/bin/plutil -extract "components.$component_index.checkoutPath" raw -o - "$MANIFEST")"
    {
      print "identity=$identity"
      print "head=$(/usr/bin/git -C "$PROJECT_DIR/$checkout_path" rev-parse HEAD)"
      print "tree=$(/usr/bin/git -C "$PROJECT_DIR/$checkout_path" rev-parse 'HEAD^{tree}')"
      print "status=$(/usr/bin/git -C "$PROJECT_DIR/$checkout_path" status --porcelain --untracked-files=all)"
    } >> "$STATE_FILE"
  fi
  (( component_index += 1 ))
done

/usr/bin/shasum -a 256 "$STATE_FILE" | /usr/bin/awk '{print $1}'
