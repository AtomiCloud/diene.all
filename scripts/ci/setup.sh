#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# ### dart-lib-setup
# #### source: dart-lib
# Resolve the whole pub workspace once at the root before any member command.
dart pub get

./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
