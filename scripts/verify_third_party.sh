#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
MANIFEST="$PROJECT_DIR/Config/third-party-components.json"

if [[ ! -s "$MANIFEST" ]]; then
  print -u2 "缺少第三方组件清单：$MANIFEST"
  exit 1
fi
/usr/bin/plutil -convert json -o /dev/null "$MANIFEST"

typeset -A artifact_components artifact_paths artifact_owners
artifact_index=0
while artifact_path="$(/usr/bin/plutil -extract "artifacts.$artifact_index.path" raw -o - "$MANIFEST" 2>/dev/null)"; do
  expected="$(/usr/bin/plutil -extract "artifacts.$artifact_index.sha256" raw -o - "$MANIFEST")"
  artifact_component=""
  if extracted_component="$(
    /usr/bin/plutil -extract "artifacts.$artifact_index.component" raw -o - "$MANIFEST" 2>/dev/null
  )"; then
    artifact_component="$extracted_component"
  fi
  actual="$(/usr/bin/shasum -a 256 "$PROJECT_DIR/$artifact_path" | /usr/bin/awk '{print $1}')"
  if [[ -n "${artifact_paths[$artifact_path]:-}" ]]; then
    print -u2 "第三方资源清单包含重复路径：$artifact_path"
    exit 1
  fi
  artifact_paths[$artifact_path]=1
  if [[ "$actual" != "$expected" ]]; then
    print -u2 "第三方资源摘要不一致：$artifact_path"
    exit 1
  fi
  if [[ -n "$artifact_component" ]]; then
    artifact_components[$artifact_component]=1
    artifact_owners[$artifact_path]="$artifact_component"
  fi
  print "$artifact_path: OK"
  (( artifact_index += 1 ))
done

typeset -A pin_version pin_revision pin_location
pin_index=0
while identity="$(/usr/bin/plutil -extract "pins.$pin_index.identity" raw -o - "$PROJECT_DIR/Package.resolved" 2>/dev/null)"; do
  pin_version[$identity]="$(/usr/bin/plutil -extract "pins.$pin_index.state.version" raw -o - "$PROJECT_DIR/Package.resolved")"
  pin_revision[$identity]="$(/usr/bin/plutil -extract "pins.$pin_index.state.revision" raw -o - "$PROJECT_DIR/Package.resolved")"
  pin_location[$identity]="$(/usr/bin/plutil -extract "pins.$pin_index.location" raw -o - "$PROJECT_DIR/Package.resolved")"
  (( pin_index += 1 ))
done

typeset -A manifest_components manifest_swiftpm bundled_components packaged_license_names
component_index=0
while identity="$(/usr/bin/plutil -extract "components.$component_index.identity" raw -o - "$MANIFEST" 2>/dev/null)"; do
  if [[ -n "${manifest_components[$identity]:-}" ]]; then
    print -u2 "第三方组件清单包含重复 identity：$identity"
    exit 1
  fi
  manifest_components[$identity]=1
  notice_name="$(/usr/bin/plutil -extract "components.$component_index.noticeName" raw -o - "$MANIFEST")"
  kind="$(/usr/bin/plutil -extract "components.$component_index.kind" raw -o - "$MANIFEST")"
  version="$(/usr/bin/plutil -extract "components.$component_index.version" raw -o - "$MANIFEST")"
  source="$(/usr/bin/plutil -extract "components.$component_index.source" raw -o - "$MANIFEST")"
  license="$(/usr/bin/plutil -extract "components.$component_index.license" raw -o - "$MANIFEST")"
  license_path="$(/usr/bin/plutil -extract "components.$component_index.licensePath" raw -o - "$MANIFEST")"
  packaged_license_name="$(/usr/bin/plutil -extract "components.$component_index.packagedLicenseName" raw -o - "$MANIFEST")"
  if [[ "$packaged_license_name" != "${packaged_license_name:t}" ||
        -n "${packaged_license_names[$packaged_license_name]:-}" ]]; then
    print -u2 "随包许可证文件名非法或重复：$identity $packaged_license_name"
    exit 1
  fi
  packaged_license_names[$packaged_license_name]=1
  [[ -s "$PROJECT_DIR/$license_path" ]] || {
    print -u2 "第三方许可证缺失：$license_path"
    exit 1
  }
  notice_line="$(/usr/bin/awk -F'|' -v expected="$notice_name" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    trim($2) == expected { print $0 }
  ' "$PROJECT_DIR/THIRD_PARTY_NOTICES.md")"
  notice_line_count="$(print -r -- "$notice_line" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')"
  if [[ "$notice_line_count" != "1" ]]; then
    print -u2 "第三方总声明缺少唯一组件记录：$identity"
    exit 1
  fi
  notice_version="$(print -r -- "$notice_line" | /usr/bin/awk -F'|' '{ value=$3; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); print value }')"
  notice_license="$(print -r -- "$notice_line" | /usr/bin/awk -F'|' '{ value=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); print value }')"
  notice_source="$(print -r -- "$notice_line" | /usr/bin/awk -F'|' '{ value=$5; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); print value }')"
  if [[ "$notice_version" != *"$version"* ||
        "$notice_license" != "$license" ||
        "$notice_source" != *"$source"* ]]; then
    print -u2 "第三方总声明与同一组件记录不一致：$identity"
    exit 1
  fi
  if [[ "$kind" == "swiftpm" ]]; then
    manifest_swiftpm[$identity]=1
    revision="$(/usr/bin/plutil -extract "components.$component_index.revision" raw -o - "$MANIFEST")"
    checkout_path="$(/usr/bin/plutil -extract "components.$component_index.checkoutPath" raw -o - "$MANIFEST")"
    if [[ "${pin_version[$identity]:-}" != "$version" ||
          "${pin_revision[$identity]:-}" != "$revision" ||
          "${pin_location[$identity]:-}" != "$source" ]]; then
      print -u2 "SwiftPM 依赖与组件清单不一致：$identity"
      exit 1
    fi
    if [[ "$notice_version" != *"$revision"* ]]; then
      print -u2 "第三方总声明缺少同一 SwiftPM 组件修订：$identity"
      exit 1
    fi
    if [[ "$(/usr/bin/git -C "$PROJECT_DIR/$checkout_path" rev-parse HEAD 2>/dev/null)" != "$revision" ]]; then
      print -u2 "SwiftPM checkout HEAD 与锁定修订不一致：$identity"
      exit 1
    fi
    if [[ -n "$(/usr/bin/git -C "$PROJECT_DIR/$checkout_path" status --porcelain --untracked-files=all)" ]]; then
      print -u2 "SwiftPM checkout 包含未提交改动：$identity"
      exit 1
    fi
  elif [[ "$kind" == "bundled" ]]; then
    bundled_components[$identity]=1
    provenance_path="$(/usr/bin/plutil -extract "components.$component_index.provenancePath" raw -o - "$MANIFEST")"
    artifact_root="$(/usr/bin/plutil -extract "components.$component_index.artifactRoot" raw -o - "$MANIFEST")"
    /usr/bin/grep -Fq -- "- Version: $version" "$PROJECT_DIR/$provenance_path" || {
      print -u2 "来源记录版本与组件清单不一致：$identity"
      exit 1
    }
    for bundled_link in "$PROJECT_DIR/$artifact_root"/**/*(@DN); do
      print -u2 "内置第三方目录不允许符号链接：${bundled_link#$PROJECT_DIR/}"
      exit 1
    done
    for bundled_path in "$PROJECT_DIR/$artifact_root"/**/*(.DN); do
      relative_bundled_path="${bundled_path#$PROJECT_DIR/}"
      if [[ "${artifact_owners[$relative_bundled_path]:-}" != "$identity" ]]; then
        print -u2 "内置第三方资源所有者不一致：$identity $relative_bundled_path"
        exit 1
      fi
    done
    if [[ "${artifact_owners[$license_path]:-}" != "$identity" ||
          "${artifact_owners[$provenance_path]:-}" != "$identity" ]]; then
      print -u2 "内置组件的许可证或来源记录所有者不一致：$identity"
      exit 1
    fi
    /usr/bin/grep -Fq -- "$source" "$PROJECT_DIR/$provenance_path" || {
      print -u2 "来源记录上游地址与组件清单不一致：$identity"
      exit 1
    }
  else
    print -u2 "未知第三方组件类型：$identity $kind"
    exit 1
  fi
  (( component_index += 1 ))
done

for identity in ${(k)pin_version}; do
  if [[ -z "${manifest_swiftpm[$identity]:-}" ]]; then
    print -u2 "Package.resolved 依赖未登记到第三方组件清单：$identity"
    exit 1
  fi
done

for identity in ${(k)artifact_components}; do
  if [[ -z "${manifest_components[$identity]:-}" ]]; then
    print -u2 "第三方资源引用了未登记组件：$identity"
    exit 1
  fi
done

for identity in ${(k)bundled_components}; do
  if [[ -z "${artifact_components[$identity]:-}" ]]; then
    print -u2 "内置第三方组件缺少受摘要保护的资源：$identity"
    exit 1
  fi
done

print "第三方组件版本、来源、许可证与资源摘要校验通过。"
