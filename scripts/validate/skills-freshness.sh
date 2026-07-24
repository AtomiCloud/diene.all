#!/usr/bin/env bash
set -euo pipefail

bash scripts/local/skills-sync.sh
git diff --exit-code -- .claude/skills/vendor

echo "✅ Vendored skills are fresh"
