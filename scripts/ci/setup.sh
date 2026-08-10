#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# Resolve the whole pub workspace once at the root before any member command.
dart pub get

# The parent replaced scripts/local/skills-sync.sh with the skills-sync binary
# and moved workspace setup to scripts/local/setup.sh, which runs the WRITE mode
# (`skills-sync sync`) and `releaser conventions`. Neither belongs in CI: both
# rewrite tracked files, and `releaser` is not in the .#ci shell at all — it
# lives in the `dev` and `releaser` groups. CI therefore runs the frozen check,
# which is the same reconciliation asked to report rather than to write.
skills-sync sync --frozen

echo "✅ Repository setup complete"
