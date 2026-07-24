#!/usr/bin/env bash
set -euo pipefail

[ -z "${GITHUB_TOKEN:-}" ] && echo "❌ 'GITHUB_TOKEN' env var not set" >&2 && exit 1

./scripts/ci/setup.sh
rm -f .git/hooks/*
[ -d node_modules ] && find node_modules -mindepth 1 -maxdepth 1 -exec rm -rf {} +
sg release -c atomi_release.yaml -i npm

echo "✅ Release complete"
