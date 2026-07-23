#!/usr/bin/env bash
set -euo pipefail

./scripts/local/skills-sync.sh

# ### dotnet-base-setup
# #### source: dotnet-base
./scripts/local/setup.sh

echo "✅ Repository setup complete"
