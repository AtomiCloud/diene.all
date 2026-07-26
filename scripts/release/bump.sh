#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

printf '%s\n' "${version#v}" >VERSION

echo "✅ VERSION stamped to ${version#v}"
