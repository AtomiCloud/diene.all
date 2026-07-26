#!/usr/bin/env bash
set -euo pipefail

# ### bun-base-setup
# #### source: bun-base
./scripts/local/setup.sh

# Synchronize dependency-provided skills only after a cold install has
# materialized node_modules. Running this before setup deletes the checked-in
# vendor tree on fresh CI runners, then makes the freshness hook restore it and
# report a false modification.
./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
