#!/usr/bin/env bash
set -euo pipefail

dart pub get
./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
