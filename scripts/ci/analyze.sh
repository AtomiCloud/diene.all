#!/usr/bin/env bash
set -euo pipefail

# Analyze runs at the workspace ROOT so every member (packages/diene_api_engine)
# is analyzed together off the single shared resolution.
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

dart pub get >/dev/null
dart analyze --fatal-infos --fatal-warnings

echo "✅ Dart analysis passed"
