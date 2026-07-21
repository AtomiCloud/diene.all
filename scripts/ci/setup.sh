#!/usr/bin/env bash
set -euo pipefail

flutter pub get
./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
