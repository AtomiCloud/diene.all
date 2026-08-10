#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# Resolve the whole pub workspace once at the root before any member command.
dart pub get

# The vendored skills tree is generated. CI must VERIFY it, never rewrite it:
# `sync --frozen` fails when the tree disagrees with the declared packages,
# which is exactly what the a-skills-sync hook asserts. The write-mode
# `skills-sync sync` belongs in the local Taskfile setup, not in CI.
skills-sync sync --frozen

echo "✅ Repository setup complete"
