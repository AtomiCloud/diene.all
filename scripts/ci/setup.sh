#!/usr/bin/env bash
set -euo pipefail

./scripts/local/skills-sync.sh
./scripts/local/setup.sh

echo "✅ Repository setup complete"
