#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

git restore --source=HEAD -- package.json
bun pm pkg set "version=${version#v}"
printf '%s\n' "${version#v}" >VERSION

echo "✅ package.json and VERSION stamped to ${version#v}"
