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
cd "${root_dir}/packages/diene_auth_engine"

echo "📦 Building pub.dev dry-run archive..."
flutter pub publish --dry-run --skip-validation

# Dartdoc and pana must be told where the Flutter SDK is. The nix dev shell does
# not set FLUTTER_ROOT, so derive the SDK root from the resolved `flutter` binary
# (…/bin/flutter -> two levels up is the SDK root, verified to contain version,
# packages/flutter, bin/cache and bin/internal) rather than hard-coding a
# /nix/store path that changes on every toolchain bump.
flutter_bin="$(command -v flutter)" || {
  echo "❌ flutter is not on PATH; pana cannot analyse a Flutter package" >&2
  exit 1
}
flutter_root="$(dirname "$(dirname "${flutter_bin}")")"
[[ -f ${flutter_root}/version && -d ${flutter_root}/packages/flutter ]] || {
  echo "❌ derived Flutter SDK root does not look like an SDK: ${flutter_root}" >&2
  exit 1
}
echo "   using Flutter SDK: ${flutter_root}"

echo "📚 Generating Dart API documentation..."
FLUTTER_ROOT="${flutter_root}" dart doc --dry-run

echo "📊 Running hermetic pana package analysis..."
pana_args=(--no-dartdoc --exit-code-threshold 0)
[[ -n ${PUB_HOSTED_URL:-} ]] && pana_args+=(--hosted-url "${PUB_HOSTED_URL}")
pana_args+=(--flutter-sdk "${flutter_root}")

dart pub global run pana "${pana_args[@]}" .

echo "✅ Dart package validation passed"
