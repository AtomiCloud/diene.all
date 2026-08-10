#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_problems"

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
