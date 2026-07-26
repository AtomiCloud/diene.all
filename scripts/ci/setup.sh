#!/usr/bin/env bash
set -euo pipefail

# ### bun-base-setup
# #### source: bun-base
./scripts/local/setup.sh

./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
