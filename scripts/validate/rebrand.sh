#!/usr/bin/env bash
set -euo pipefail

# Fixed strings via a literal pattern file (rg -F -f), never an ERE: 'Foo (Prod)' is a name, not a pattern.
app_name="$(yq '.app_name' lpsm.yaml)"
domain="$(yq '.domain' lpsm.yaml)"
platform="$(yq '.platform' lpsm.yaml)"
service="$(yq '.service' lpsm.yaml)"
landscapes="$(yq -N -r '.landscapes[].name' lpsm.yaml)"
[ -z "${app_name}" ] || [ "${app_name}" = "null" ] && echo "❌ rebrand guard cannot derive app_name" >&2 && exit 1
[ -z "${domain}" ] || [ "${domain}" = "null" ] && echo "❌ rebrand guard cannot derive domain" >&2 && exit 1
[ -z "${platform}" ] || [ "${platform}" = "null" ] && echo "❌ rebrand guard cannot derive platform" >&2 && exit 1
[ -z "${service}" ] || [ "${service}" = "null" ] && echo "❌ rebrand guard cannot derive service" >&2 && exit 1
[ -z "${landscapes}" ] && echo "❌ rebrand guard cannot derive any landscape" >&2 && exit 1

# Fail closed: every LPSM landscape must ship a config/<landscape>.yaml (comm lists any that do not).
missing="$(comm -23 <(printf '%s\n' "${landscapes}" | sort) <(printf '%s\n' config/*.yaml | sed 's#^config/##; s#\.yaml$##' | sort))"
[ -n "${missing}" ] && echo "❌ rebrand guard: missing config/<landscape>.yaml for: ${missing}" >&2 && exit 1

mapfile -t config_files < <(printf '%s\n' "${landscapes}" | sed 's#.*#config/&.yaml#')

# Fail closed on any empty/null forbidden auth or API value (filename names the offending config).
bad="$(yq -N -r '(.auth.endpoint, .auth.resource, .api.baseUrl) | select((. // "") == "") | filename' "${config_files[@]}" | sort -u)"
[ -n "${bad}" ] && echo "❌ rebrand guard: empty/null auth or API value in: ${bad}" >&2 && exit 1

# Bare platform/service tokens are inputs only; forbidding them would flag ordinary Dart.
patterns="$(mktemp)"
trap 'rm -f "${patterns}"' EXIT INT TERM
# shellcheck disable=SC2016 # $r is a yq document variable, not a shell expansion
yq -N -r '.app_name, "https://auth." + .platform, "https://api." + .platform, (. as $r | .landscapes[] | $r.domain + "." + .name + "." + $r.platform + "." + $r.service)' lpsm.yaml >"${patterns}"
yq -N -r '.auth.endpoint, .auth.resource, .api.baseUrl' "${config_files[@]}" >>"${patterns}"

# Prove literal matching on a synthetic metacharacter value instead of mutating the repository.
literal_probe='Foo (Prod) [Beta] *'
! printf 'const appName = "%s";\n' "${literal_probe}" | rg -qF -e "${literal_probe}" && echo "❌ rebrand guard is not matching derived values literally" >&2 && exit 1

rg -nF -f "${patterns}" lib --glob '*.dart' --glob '!generated/**' && echo "❌ branding, auth, or store identity is hardcoded in Dart" >&2 && exit 1
rg -q 'config\.branding\.logoAsset' lib/app.dart || {
  echo "❌ mobile logo is not config-driven" >&2
  exit 1
}
rg -q 'config\.branding\.appName' lib/app.dart || {
  echo "❌ app name is not config-driven" >&2
  exit 1
}
rg -q 'config\.auth\.(endpoint|clientId|redirectUri)' lib/auth/logto_auth_gateway.dart || {
  echo "❌ Logto identity is not config-driven" >&2
  exit 1
}
if rg -n 'NEON_|NeonAppGroup|NeonWidget|alcohol_neon|LazyTax' . \
  --glob '!step5-work/**' --glob '!Changelog.md' --glob '!probes/**' \
  --glob '!scripts/validate/rebrand.sh'; then
  echo "❌ donor branding leaked into flutter-base" >&2
  exit 1
fi

echo "✅ branding, ASO, and auth values remain config-driven"
