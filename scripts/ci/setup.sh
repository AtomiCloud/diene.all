#!/usr/bin/env bash
set -euo pipefail

# ### workspace-setup
# #### source: workspace
bash ./scripts/local/skills-sync.sh

# ### workspace-setup-complete
# #### source: workspace
echo "✅ Repository setup complete"
