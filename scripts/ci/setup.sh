#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

dart pub get
./scripts/local/skills-sync.sh

echo "✅ Dart dependencies and installed package skills are ready"
