#!/usr/bin/env bash
set -euo pipefail

target="${*: -1}"
fixture="${target%/...}/govulncheck.json"

[ ! -f "${fixture}" ] && echo "✅ Vulnerability fixture scanner passed" && exit 0
jq -e '.vulnerabilities | length > 0' "${fixture}" >/dev/null
echo "GO-2021-0113: pinned vulnerable fixture detected" >&2
exit 1
