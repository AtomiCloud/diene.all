#!/usr/bin/env bash
set -euo pipefail

./scripts/validate/publish-version.sh
[[ -z ${PUB_CREDENTIALS_JSON:-} ]] && echo "❌ PUB_CREDENTIALS_JSON must be set from the organization secret" >&2 && exit 1

./scripts/ci/setup.sh

credentials_dir="${HOME}/.config/dart"
credentials_file="${credentials_dir}/pub-credentials.json"
mkdir -p "${credentials_dir}"
umask 077
printf '%s' "${PUB_CREDENTIALS_JSON}" >"${credentials_file}"
trap 'rm -f "${credentials_file}"' EXIT

echo "🚀 Publishing diene_result ${GITHUB_REF_NAME#v} to pub.dev..."
dart pub publish --force

echo "✅ Published diene_result ${GITHUB_REF_NAME#v}"
