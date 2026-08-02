#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_dir="${1:-${repo_root}/config}"
target_dir="${2:-${repo_root}/chart/files/config}"
allowed_root="$(realpath -m "${repo_root}/chart/files")"
target_abs="$(realpath -m "${target_dir}")"

[ ! -d "${source_dir}" ] && echo "❌ config source '${source_dir}' does not exist" >&2 && exit 1
case "${target_abs}" in
"${allowed_root}"/*) ;;
*)
  echo "❌ refusing to vendor into '${target_dir}': not under chart/files/" >&2
  exit 1
  ;;
esac

mkdir -p "${target_abs}"
find "${target_abs}" -maxdepth 1 -type f -name '*.yaml' -delete
find "${source_dir}" -maxdepth 1 -type f -name '*.yaml' -exec cp {} "${target_abs}/" \;

[ -z "$(find "${target_abs}" -maxdepth 1 -type f -name '*.yaml' -print -quit)" ] && echo "❌ no config YAML files were vendored" >&2 && exit 1

echo "✅ External config vendored into ${target_abs}"
