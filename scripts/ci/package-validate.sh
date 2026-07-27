#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh
./scripts/validate/dart-package.sh
./scripts/validate/release-policy.sh
# ### lib-dart-e2e-package-validate
# #### source: lib/dart/e2e
# Archive completeness. The dry-run below cannot catch an over-broad .pubignore
# pattern, because the dry-run validates the WORKING TREE while the omission
# exists only in the ARCHIVE — that is exactly how both published
# diene_auth_engine releases shipped unusable.
./scripts/validate/publish-archive.sh
# NOTE: scripts/validate/c0-release.sh is deliberately NOT invoked here, and the
# script is deliberately NOT carried on this branch. It validates a vendored
# `contracts/c0/` RELEASE.json + SHA256SUMS tree — an asset the api-engine sibling
# owns and this node does not have. diene_e2e consumes C0 through a DIFFERENT and
# equally-gated shape: it vendors the single `identity.json` case it needs, with
# its digest recorded in packages/diene_e2e/test/fixtures/c0/PROVENANCE.md, pinned
# byte-for-byte by .prettierignore, and asserted by
# test/conformance/app_handoff_conformance_test.dart. Wiring a gate for an absent
# tree would have been a permanent red that teaches readers to ignore the gate.
./scripts/validate/c0-fixture-provenance.sh

# pub.dev dry-run and pana score run against the publishable member.
cd "${root_dir}/packages/diene_e2e"

echo "📦 Running pub.dev publish dry-run..."
flutter pub publish --dry-run

echo "📊 Running pana package analysis..."
pana_args=(--exit-code-threshold 0)
[[ -n ${PUB_HOSTED_URL:-} ]] && pana_args+=(--hosted-url "${PUB_HOSTED_URL}")

# ### lib-dart-e2e-pana-flutter-sdk
# #### source: lib/dart/e2e
# pana must be TOLD where the Flutter SDK is. It shells out to `dart pub` to
# resolve the package under analysis, and for a Flutter package that fails with
# "Because diene_e2e requires the Flutter SDK, version solving failed"
# unless pana knows to use `flutter pub` instead.
#
# MEASURED at b00d4c5, and the measurement corrects a plausible-sounding wrong
# diagnosis: `flutter` IS on PATH in .#ci
# (/nix/store/…-flutter-wrapped-3.44.4-sdk-links/bin/flutter). What is missing is
# FLUTTER_ROOT, which the nix dev shell does not export — and pana does NOT
# auto-detect the SDK from PATH. A first detached run therefore ended
# PANA_RC=127 at 30/160 points having logged "Flutter SDK path was not
# specified… will use the default Dart SDK" and "Flutter rootPath is missing".
# That is a defect in THIS SCRIPT, not an unusable venue: reading it as "no
# Flutter here, rerun elsewhere" would send the next reader hunting for a
# different machine instead of passing one flag.
#
# The root is derived from the RESOLVED binary (…/bin/flutter -> two levels up)
# rather than hard-coded, so a toolchain bump that changes the store path cannot
# silently stale it, and the derivation is asserted rather than assumed.
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
