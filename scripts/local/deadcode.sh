#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

dart pub get
production_root="$(mktemp -d)"
trap 'rm -rf "${production_root}"' EXIT

echo "🔎 Repository dead-code pass (library + tests + example)"
dart run dart_code_linter:metrics check-unused-code lib test example
dart run dart_code_linter:metrics check-unused-files lib test example

echo "🔎 Production dead-code pass (published entrypoints, tests excluded)"
cp pubspec.yaml analysis_options.yaml "${production_root}/"
cp -R lib "${production_root}/lib"
mkdir -p "${production_root}/bin"
cp tool/deadcode_entrypoints.dart "${production_root}/bin/main.dart"
(
  cd "${production_root}"
  dart pub get
  dart run dart_code_linter:metrics check-unused-code .
  dart run dart_code_linter:metrics check-unused-files .
)

echo "✅ Both dead-code passes are clean without exclusions"
