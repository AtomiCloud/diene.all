#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
settings="config/settings.yaml"
identity_values="$(
  for file in "${settings}" config/*.settings.yaml; do
    yq -r '[
      .app.landscape, .app.platform, .app.service, .app.module, .app.version,
      .errorPortal.landscape, .errorPortal.platform, .errorPortal.service, .errorPortal.module,
      (.api.backends[]? | .coordinate.landscape, .coordinate.platform, .coordinate.service, .coordinate.module,
        .resource.landscape, .resource.platform, .resource.service, .resource.resourceName)
    ] | .[] | select(tag == "!!str" and length > 0)' "${file}"
  done | sort -u
)"
auth_values="$(
  for file in "${settings}" config/*.settings.yaml; do
    yq -r '[
      .auth.logto.endpoint, .auth.logto.appId,
      .auth.logto.management.endpoint, .auth.logto.management.clientId,
      (.api.backends[]? | .baseUrl)
    ] | .[] | select(tag == "!!str" and length > 0)' "${file}"
  done | sort -u
)"

echo "🏷️ Checking config-driven identity and auth values..."
while IFS= read -r value; do
  hardcoded_identity="$(rg -l --pcre2 "(['\"\x60])\\Q${value}\\E\\1" src --glob '*.ts' | rg -v '^src/index\.ts$' || true)"
  [[ -n ${hardcoded_identity} ]] && echo "❌ Per-instance identity '${value}' is hardcoded outside the composition root: ${hardcoded_identity}" >&2 && exit 1
done <<<"${identity_values}"
while IFS= read -r value; do
  hardcoded_auth="$(rg -l --pcre2 "(['\"\x60])\\Q${value}\\E\\1" src --glob '*.ts' || true)"
  [[ -n ${hardcoded_auth} ]] && echo "❌ Auth/API endpoint or client identity is hardcoded in source: ${hardcoded_auth}" >&2 && exit 1
done <<<"${auth_values}"
echo "✅ Identity, branding, and auth values remain config-driven"
