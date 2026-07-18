#!/usr/bin/env bash
set -euo pipefail

./scripts/local/skills-sync.sh

# ### go-base
# #### source: go-base
go mod download

echo "✅ Repository setup complete"
