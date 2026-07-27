#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh
./scripts/validate/dart-package.sh
./scripts/validate/release-policy.sh

# pub.dev dry-run and pana score run against the publishable member.
cd "${root_dir}/packages/diene_auth_engine"

echo "📦 Running pub.dev publish dry-run..."
flutter pub publish --dry-run

echo "📊 Running pana package analysis..."
pana_args=(--exit-code-threshold 0)
[[ -n ${PUB_HOSTED_URL:-} ]] && pana_args+=(--hosted-url "${PUB_HOSTED_URL}")

# pana must be told where the FLUTTER SDK is. It shells out to `dart pub` to
# resolve the package under analysis, and for a Flutter package that fails with
# "Because diene_auth_engine requires the Flutter SDK, version solving failed"
# unless pana knows to use `flutter pub` instead. The nix dev shell does not set
# FLUTTER_ROOT, so derive the SDK root from the resolved `flutter` binary
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
pana_args+=(--flutter-sdk "${flutter_root}")

dart pub global run pana "${pana_args[@]}" .

echo "✅ Dart package validation passed"
