#!/usr/bin/env bash
set -euo pipefail

./scripts/local/skills-sync.sh

# ### bun-base-setup
# #### source: bun-base
./scripts/local/setup.sh

echo "✅ Repository setup complete"
