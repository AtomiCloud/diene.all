#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# Resolve the whole pub workspace once at the root before any member command.
flutter pub get

# pana cannot live in this workspace's resolution at all. A Dart pub workspace
# shares ONE resolution across every member, so pana is solved against
# flutter_test's pins and is unsolvable ("pana >=0.23.13 is incompatible with
# flutter_test from sdk" — it needs analyzer ^13 and test ^1.26.2). Moving it to
# the workspace ROOT manifest does not help: same shared resolution. So it is
# activated into its OWN isolated resolution, version-PINNED and idempotent.
# Deliberately `dart pub global`, never `flutter pub global`.
dart pub global activate --overwrite pana 0.23.14

# The parent DELETED scripts/local/skills-sync.sh and replaced it with the
# registry `skills-sync` binary. That deletion merged cleanly while this caller
# survived, so under `set -euo pipefail` every CI entrypoint that sources this
# script — test.sh, publish.sh, deadcode.sh, package-validate.sh — would have
# aborted here on a missing file.
#
# `--frozen` deliberately, because this runs in CI: the write mode belongs to
# the local Taskfile setup, and a CI step that regenerates a tracked tree turns
# a drifted vendor directory into a dirty working tree instead of a red gate.
skills-sync sync --frozen

echo "✅ Repository setup complete"
