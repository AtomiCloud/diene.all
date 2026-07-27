#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
values="$(mktemp)"
offenses="$(mktemp)"
sources="$(mktemp)"
trap 'rm -f "${values}" "${offenses}" "${sources}"' EXIT
roots=()
for root in cmd lib adapters; do
  [ -d "${root}" ] && roots+=("${root}")
done

echo "🏷️ Checking config-driven identity and auth values..."
shopt -s nullglob
config_files=(config/settings.yaml config/*.settings.yaml)
[ "${#config_files[@]}" -ne 0 ] || {
  echo "❌ no configuration files found — refusing an empty identity scan" >&2
  exit 1
}
[ "${#roots[@]}" -ne 0 ] || {
  echo "❌ no shipped Go source roots found — refusing an empty identity scan" >&2
  exit 1
}
for file in "${config_files[@]}"; do
  [ -s "${file}" ] || {
    echo "❌ configuration subject ${file} is missing or empty" >&2
    exit 1
  }
  yq -r '[
    .app.landscape, .app.platform, .app.service, .app.module, .app.version,
    .errorPortal.landscape, .errorPortal.platform, .errorPortal.service, .errorPortal.module,
    .auth.idp.issuer, .auth.idp.audience, .auth.idp.jwksUri,
    .auth.idp.management.endpoint, .auth.idp.management.resource, .auth.idp.management.clientId,
    .auth.minting.tokenEndpoint, .auth.minting.clientId,
    (.api.backends[]? | .baseUrl, .resource, .indicator)
  ] | .[] | select(tag == "!!str" and length > 0)' "${file}"
done | sort -u >"${values}"
rg --files "${roots[@]}" --glob '*.go' --glob '!**/*_test.go' | sort -u >"${sources}"
value_count="$(wc -l <"${values}" | tr -d ' ')"
source_count="$(wc -l <"${sources}" | tr -d ' ')"
[ "${value_count}" -ne 0 ] || {
  echo "❌ no identity/auth values found in configuration — refusing an empty identity scan" >&2
  exit 1
}
[ "${source_count}" -ne 0 ] || {
  echo "❌ no shipped Go files found — refusing an empty identity scan" >&2
  exit 1
}
while IFS= read -r value; do
  pattern="([\"'\`])\\Q${value}\\E\\1"
  rg -n --pcre2 "${pattern}" "${roots[@]}" --glob '*.go' --glob '!**/*_test.go' |
    sed -E '\#^cmd/.+:[0-9]+:[[:space:]]*Use:[[:space:]]*"[^"]*",[[:space:]]*$#d' \
      >>"${offenses}" || true
done <"${values}"
sort -u -o "${offenses}" "${offenses}"
if [ -s "${offenses}" ]; then
  sed 's/^/❌ hardcoded config identity: /' "${offenses}" >&2
  exit 1
fi
echo "${value_count} identity/auth values from ${#config_files[@]} config files, ${source_count} shipped Go files"
echo "0 hardcoded identity/auth values in shipped Go source"
echo "✅ Identity, branding, and auth values remain config-driven"
