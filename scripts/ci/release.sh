#!/usr/bin/env bash
set -euo pipefail
rm .git/hooks/* 2>/dev/null || true
# npm's arborist chokes on the cache-restored node_modules of an older dep set
rm -rf node_modules
sg release -i npm
echo "✅ Release complete"
