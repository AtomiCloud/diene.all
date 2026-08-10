#!/usr/bin/env bash
set -euo pipefail

# ### workspace-setup
# #### source: workspace
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# ### go-consumer
# #### source: go-consumer
./scripts/local/setup.sh

# ### workspace-setup-complete
# #### source: workspace
echo "✅ Repository setup complete"
