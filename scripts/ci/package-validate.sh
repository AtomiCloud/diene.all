#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh
./scripts/validate/dart-package.sh
./scripts/validate/release-policy.sh

# pub.dev dry-run and pana score run against the publishable member.
cd "${root_dir}/packages/diene_interfaces"

echo "📦 Running pub.dev publish dry-run..."
dart pub publish --dry-run

echo "📊 Running pana package analysis..."
pana_args=(--exit-code-threshold 0)
[[ -n ${PUB_HOSTED_URL:-} ]] && pana_args+=(--hosted-url "${PUB_HOSTED_URL}")
dart run pana "${pana_args[@]}" .

echo "✅ Dart package validation passed"
