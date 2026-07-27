#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_config"

# Resolve the whole workspace once at the root.
dart pub get

production_root="$(mktemp -d)"
trap 'rm -rf "${production_root}"' EXIT

echo "🔎 Repository dead-code pass (library + tests + example)"
(
  cd "${member_dir}"
  dart run dart_code_linter:metrics check-unused-code lib test example
  dart run dart_code_linter:metrics check-unused-files lib test example
)

echo "🔎 Production dead-code pass (published entrypoints, tests excluded)"
cp "${member_dir}/analysis_options.yaml" "${production_root}/analysis_options.yaml"
# Standalone manifest: drop `resolution: workspace` so `dart pub get` resolves
# outside the pub workspace. Runtime dependencies (if any) are preserved.
yq 'del(.resolution)' "${member_dir}/pubspec.yaml" >"${production_root}/pubspec.yaml"
# A developer-local `pubspec_overrides.yaml` is deliberately NOT copied here.
# This fixture stands in for a clean external consumer, so it must resolve the
# same hosted bytes pub.dev would serve. Copying an override in would let the
# production dead-code pass succeed against a local path/override graph that no
# consumer can reproduce — evidence bound to bytes that only exist on this
# machine. Fail closed instead: an override present at this point means the
# proof venue is not clean.
if [[ -f "${member_dir}/pubspec_overrides.yaml" ]]; then
  echo "❌ ${member_dir}/pubspec_overrides.yaml exists; the standalone dead-code proof must resolve the hosted graph, not a local override" >&2
  exit 1
fi
cp -R "${member_dir}/lib" "${production_root}/lib"
mkdir -p "${production_root}/bin"
cp "${member_dir}/tool/deadcode_entrypoints.dart" "${production_root}/bin/main.dart"
(
  cd "${production_root}"
  dart pub get
  dart run dart_code_linter:metrics check-unused-code .
  dart run dart_code_linter:metrics check-unused-files .
)

echo "✅ Both dead-code passes are clean without exclusions"
