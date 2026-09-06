#!/bin/zsh
set -euo pipefail

identity="${MODU_SIGNING_IDENTITY-EDAF5540E35BBA649726925FC5E5B0176BB07AEB}"
identity="${(U)identity}"
if [[ ${#identity} != 40 || "$identity" == *[^0-9A-F]* ]]; then
  print -u2 "MODU_SIGNING_IDENTITY 必须为签名证书的完整 40 位 SHA-1；不支持空值或 ad-hoc 签名。"
  exit 1
fi

if ! identities="$(/usr/bin/security find-identity -v -p codesigning)"; then
  print -u2 "无法读取钥匙串中的代码签名身份。"
  exit 1
fi
if ! print -r -- "$identities" | /usr/bin/awk -v identity="$identity" \
  '$2 == identity { found = 1 } END { exit !found }'; then
  print -u2 "找不到有效签名身份：$identity。请在构建机器钥匙串中安装对应证书及私钥，或设置 MODU_SIGNING_IDENTITY。不会回退到 ad-hoc 签名。"
  exit 1
fi

print -r -- "$identity"
