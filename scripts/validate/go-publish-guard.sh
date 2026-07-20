#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"

[ -z "${tag}" ] && echo "❌ release tag not set" >&2 && exit 1
[[ ! ${tag} =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] && echo "❌ release tag '${tag}' must match vX.Y.Z" >&2 && exit 1
./scripts/validate/go-module-path.sh

echo "✅ Go publication guard accepted ${tag}"
