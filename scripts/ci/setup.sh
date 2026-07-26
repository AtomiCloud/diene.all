#!/usr/bin/env bash
set -euo pipefail

./scripts/local/skills-sync.sh

# ### bun-base-setup
# #### source: bun-base
./scripts/local/setup.sh

# Dependency-bearing libraries can only vendor installed package skills after setup.
./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
