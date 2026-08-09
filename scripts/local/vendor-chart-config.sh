#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:-config}"
target_dir="${2:-chart/files/config}"

[ ! -d "${source_dir}" ] && echo "❌ config source '${source_dir}' does not exist" >&2 && exit 1

mkdir -p "${target_dir}"
find "${target_dir}" -maxdepth 1 -type f -name '*.yaml' -delete
find "${source_dir}" -maxdepth 1 -type f -name '*.yaml' -exec cp {} "${target_dir}/" \;

[ -z "$(find "${target_dir}" -maxdepth 1 -type f -name '*.yaml' -print -quit)" ] && echo "❌ no config YAML files were vendored" >&2 && exit 1

echo "✅ External config vendored into ${target_dir}"
