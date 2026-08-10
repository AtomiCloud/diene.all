#!/usr/bin/env bash
set -euo pipefail

[ -z "${GITHUB_TOKEN:-}" ] && echo "❌ 'GITHUB_TOKEN' env var not set" >&2 && exit 1
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

rm -f .git/hooks/*
releaser release -c release.yaml

echo "✅ Release complete"
