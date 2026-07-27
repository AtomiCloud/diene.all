#!/usr/bin/env bash
set -euo pipefail

# Analyze runs at the workspace ROOT so every member (packages/diene_auth_engine)
# is analyzed together off the single shared resolution.
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

flutter pub get >/dev/null
# `flutter analyze`, NOT `dart analyze`. Measured at this CWD: `dart analyze`
# resolves the ROOT package (diene_auth_engine_workspace), which declares no
# dependencies, so every member file importing package:flutter/*,
# package:flutter_test/*, package:logto_dart_sdk/* or package:diene_auth_engine/*
# reports uri_does_not_exist — 47 of those plus 1370 cascading undefined_*
# errors. `flutter analyze` understands the workspace and reports the real
# result. (`dart analyze` run from INSIDE packages/diene_auth_engine agrees with
# flutter analyze; the root invocation is the one that breaks.) flutter analyze
# already treats infos as failures, so --fatal-infos/--fatal-warnings are not
# passed — the strictness is preserved, not relaxed.
flutter analyze

echo "✅ Dart analysis passed"
