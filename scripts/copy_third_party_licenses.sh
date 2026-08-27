#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
MANIFEST="$PROJECT_DIR/Config/third-party-components.json"
DESTINATION="${1:-}"

if [[ -z "$DESTINATION" || "$DESTINATION" != "$PROJECT_DIR/build/MoDu.app/Contents/Resources/ThirdPartyLicenses" ]]; then
  print -u2 "拒绝复制到非预期许可证目录：$DESTINATION"
  exit 1
fi

/bin/mkdir -p "$DESTINATION"
component_index=0
while identity="$(/usr/bin/plutil -extract "components.$component_index.identity" raw -o - "$MANIFEST" 2>/dev/null)"; do
  license_path="$(/usr/bin/plutil -extract "components.$component_index.licensePath" raw -o - "$MANIFEST")"
  packaged_name="$(/usr/bin/plutil -extract "components.$component_index.packagedLicenseName" raw -o - "$MANIFEST")"
  source_path="$PROJECT_DIR/$license_path"
  destination_path="$DESTINATION/$packaged_name"
  /bin/cp "$source_path" "$destination_path"
  /usr/bin/cmp -s "$source_path" "$destination_path" || {
    print -u2 "随包许可证复制校验失败：$identity"
    exit 1
  }
  (( component_index += 1 ))
done
