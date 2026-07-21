#!/usr/bin/env bash
set -euo pipefail

landscape="${1:-}"
[ -z "${landscape}" ] && echo "❌ usage: ios-signing-targets.sh <landscape>" >&2 && exit 1

root="$(cd "$(dirname "$0")/../.." && pwd)"
domain="$(yq '.domain' "${root}/lpsm.yaml")"
platform="$(yq '.platform' "${root}/lpsm.yaml")"
service="$(yq '.service' "${root}/lpsm.yaml")"
prefix="${domain}.${landscape}.${platform}.${service}."

yq -e ".landscapes[] | select(.name == \"${landscape}\")" "${root}/lpsm.yaml" >/dev/null || {
  echo "❌ unknown landscape '${landscape}'" >&2
  exit 1
}

sed -n "s/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = \(${prefix//./\\.}[a-z0-9.]*\);$/\1/p" \
  "${root}/ios/Runner.xcodeproj/project.pbxproj" |
  grep -v '\.tests$' |
  sort -u |
  awk '{ print length, $0 }' |
  sort -n |
  cut -d' ' -f2-
