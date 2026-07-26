#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/local/skills-sync.sh

# ### go-consumer
# #### source: go-consumer
./scripts/local/setup.sh

echo "✅ Repository setup complete"
