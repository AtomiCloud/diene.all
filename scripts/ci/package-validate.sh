#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh
./scripts/validate/dart-package.sh
./scripts/validate/release-policy.sh

# Build the publish archive and run the hermetic Pana categories against the
# publishable member. Full `dart pub publish --dry-run` always refreshes the
# advisory database; `--skip-validation` deliberately limits this step to the
# offline-safe archive build while the repository validators and Pana retain
# semantic coverage.
cd "${root_dir}/packages/diene_dart_lib"

echo "📦 Building pub.dev dry-run archive..."
dart pub publish --dry-run --skip-validation

echo "📚 Generating Dart API documentation..."
dart doc --dry-run

echo "📊 Running hermetic pana package analysis..."
pana_args=(--no-dartdoc --exit-code-threshold 0)
[[ -n ${PUB_HOSTED_URL:-} ]] && pana_args+=(--hosted-url "${PUB_HOSTED_URL}")
dart run pana "${pana_args[@]}" .

echo "✅ Dart package validation passed"
