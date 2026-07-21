#!/usr/bin/env bash
set -euo pipefail

dart pub get
dart format --output=none --set-exit-if-changed lib/diene_core_utils.dart lib/src test tool
dart analyze
dart test
pls test:unit:coverage
pls test:meta
pls deadcode
./scripts/validate/manifest-tag.sh "v$(yq '.version' pubspec.yaml)"
dart pub publish --dry-run
