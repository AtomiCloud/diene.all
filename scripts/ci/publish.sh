#!/usr/bin/env bash
set -euo pipefail

# pub.dev publish path. Authored for the mirror CD; REAL publication is
# conductor-gated (P-TOKEN tail) and never runs from an implementation lane.
# Credentials arrive as the GitHub secret PUB_CREDENTIALS_JSON, written to the
# pub config dir before this runs.

dart pub get
dart format --output=none --set-exit-if-changed lib test
dart analyze
dart test
./scripts/validate/manifest-tag.sh check
dart pub publish --dry-run

if [ "${DIENE_PUBLISH:-false}" = "true" ]; then
  [ -z "${PUB_CREDENTIALS_JSON:-}" ] && echo "❌ PUB_CREDENTIALS_JSON not set" >&2 && exit 1
  config_dir="${HOME}/.config/dart"
  mkdir -p "${config_dir}"
  printf '%s' "${PUB_CREDENTIALS_JSON}" >"${config_dir}/pub-credentials.json"
  echo "🚀 Publishing diene_api_engine to pub.dev..."
  dart pub publish --force
  echo "✅ Published"
else
  echo "🛑 DIENE_PUBLISH not set — dry-run only (real publish is conductor-gated)"
fi
