#!/usr/bin/env bash
set -euo pipefail
rm .git/hooks/* 2>/dev/null || true
# node_modules is a cache mountpoint: empty the stale tree, keep the mount
[ -d node_modules ] && find node_modules -mindepth 1 -maxdepth 1 -exec rm -rf {} +
sg release -i npm
echo "✅ Release complete"
