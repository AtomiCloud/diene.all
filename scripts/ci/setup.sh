#!/usr/bin/env bash
set -euo pipefail

./scripts/local/skills-sync.sh

# ### bun-base-setup
# #### source: bun-base
./scripts/local/setup.sh

# Dependency-provided skills only exist after the package install above.
./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
