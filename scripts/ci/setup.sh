#!/usr/bin/env bash
set -euo pipefail

# ### workspace-setup
# #### source: workspace
./scripts/local/skills-sync.sh

# ### go-base
# #### source: go-base
go mod download

# ### workspace-setup-complete
# #### source: workspace
echo "✅ Repository setup complete"
