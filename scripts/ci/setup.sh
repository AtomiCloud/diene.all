#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# ### dart-lib-setup
# #### source: dart-lib
# Resolve the whole pub workspace once at the root before any member command.
flutter pub get

# ### lib-dart-auth-engine-setup
# #### source: lib/dart/auth-engine
# pana is NOT a dev_dependency here, unlike the pure-Dart siblings: a pub
# WORKSPACE shares one resolution, and pana (analyzer ^13, test ^1.26.2) is
# unsolvable against flutter_test's SDK pins (matcher 0.12.19, test_api 0.7.11).
# So it is activated into its OWN isolated resolution and invoked as
# `dart pub global run pana`. Version is PINNED so the score gate is
# reproducible; --overwrite makes re-running setup idempotent.
dart pub global activate --overwrite pana "${PANA_VERSION:-0.23.14}"

./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
