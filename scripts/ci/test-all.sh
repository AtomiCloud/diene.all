#!/usr/bin/env bash
set -euo pipefail

# Resolve the whole workspace at the root, then run the member's full suite.
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

flutter pub get >/dev/null
cd "${root_dir}/packages/diene_api_engine"
flutter test
