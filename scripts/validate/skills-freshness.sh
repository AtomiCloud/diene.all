#!/usr/bin/env bash
set -euo pipefail

bash scripts/local/skills-sync.sh check

echo "✅ Vendored skills are fresh"
