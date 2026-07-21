#!/usr/bin/env bash
set -euo pipefail

[ -z "${GITHUB_TOKEN:-}" ] && echo "❌ 'GITHUB_TOKEN' env var not set" >&2 && exit 1

./scripts/ci/setup.sh
rm -f .git/hooks/*
releaser release -c atomi_release.yaml

echo "✅ Release complete"
