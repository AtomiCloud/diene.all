#!/usr/bin/env bash
set -euo pipefail

# ### workspace-setup
# #### source: workspace
./scripts/local/skills-sync.sh

# ### bun-base-setup
# #### source: bun-base
./scripts/local/setup.sh

# ### workspace-setup-complete
# #### source: workspace
echo "✅ Repository setup complete"
