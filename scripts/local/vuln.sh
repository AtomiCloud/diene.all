#!/usr/bin/env bash
set -euo pipefail

scanner="${GOVULNCHECK_BIN:-govulncheck}"
target="${GOVULNCHECK_TARGET:-./...}"

"${scanner}" -mode=source "${target}"

echo "✅ Go vulnerability scan passed"
