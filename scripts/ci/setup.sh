#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# ### dart-lib-setup
# #### source: dart-lib
# Resolve the whole pub workspace once at the root before any member command.
flutter pub get

# ### lib-dart-api-engine-setup
# #### source: lib/dart/api-engine
# pana cannot live in this workspace's resolution at all. A Dart pub workspace
# shares ONE resolution across every member, so pana is solved against
# flutter_test's pins and is unsolvable ("pana >=0.23.13 is incompatible with
# flutter_test from sdk" — it needs analyzer ^13 and test ^1.26.2). Moving it to
# the workspace ROOT manifest does not help: same shared resolution. So it is
# activated into its OWN isolated resolution, version-PINNED and idempotent.
# Deliberately `dart pub global`, never `flutter pub global`.
dart pub global activate --overwrite pana 0.23.14

./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
