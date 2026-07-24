#!/usr/bin/env bash
set -euo pipefail

./scripts/local/skills-sync.sh

# ### bun-base-setup
# #### source: bun-base
./scripts/local/setup.sh

# ### bun-interfaces-setup
# #### source: lib/bun/interfaces
./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
