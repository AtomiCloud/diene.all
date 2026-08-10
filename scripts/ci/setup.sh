#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# Resolve the whole pub workspace once at the root before any member command.
dart pub get

skills-sync sync --frozen

echo "✅ Repository setup complete"
