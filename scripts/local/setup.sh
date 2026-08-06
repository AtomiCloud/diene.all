#!/usr/bin/env bash
set -euo pipefail

releaser conventions -c release.yaml
skills-sync sync

echo "✅ setup completed"
