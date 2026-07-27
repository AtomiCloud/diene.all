#!/usr/bin/env bash
set -euo pipefail

# ### workspace-setup
# #### source: workspace
./scripts/local/skills-sync.sh

# ### dotnet-base-setup
# #### source: dotnet-base
./scripts/local/setup.sh

# ### workspace-setup-complete
# #### source: workspace
echo "✅ Repository setup complete"
