#!/usr/bin/env bash
set -euo pipefail

# ### bun-base-setup
# #### source: bun-base
./scripts/local/setup.sh

# ### nextjs-frontend-setup
# #### source: nextjs-frontend
# skills-sync reads node_modules, so it must run AFTER the install: on a fresh
# runner the reverse order staged an empty vendor dir, and the freshness hook
# then read its own restore as a modification.
./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
