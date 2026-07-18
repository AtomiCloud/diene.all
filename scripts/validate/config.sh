#!/usr/bin/env bash
set -euo pipefail

for landscape in lapras pichu pikachu raichu; do
  file="config/${landscape}.yaml"
  [ "$(yq '.app.landscape' "${file}")" != "${landscape}" ] && echo "❌ ${file} landscape mismatch" >&2 && exit 1
  yq -e '.branding.appName and .branding.iconAsset and .theme.primary and .auth.endpoint and .auth.redirectUri and .api.baseUrl' "${file}" >/dev/null || {
    echo "❌ ${file} is missing required overlay keys" >&2
    exit 1
  }
done
yq -e '.session.accessMinutes == 10 and .session.refreshDays == 14' config/base.yaml >/dev/null || {
  echo "❌ session policy must remain 10 minutes / 14 days" >&2
  exit 1
}
flutter test test/config_test.dart

echo "✅ configuration layers and schema-facing values conform"
