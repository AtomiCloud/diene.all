#!/usr/bin/env bash
set -euo pipefail

./scripts/local/vuln.sh

echo "✅ CI Go vulnerability gate passed"
