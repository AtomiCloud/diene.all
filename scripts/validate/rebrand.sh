#!/usr/bin/env bash
set -euo pipefail

forbidden='Diene Mobile|cloud\.atomi\.(lapras|pichu|pikachu|raichu)\.platform\.service|https://(auth|api)\.platform'
if rg -n "${forbidden}" lib --glob '*.dart' --glob '!generated/**'; then
  echo "❌ branding, auth, or store identity is hardcoded in Dart" >&2
  exit 1
fi
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
