#!/usr/bin/env bash
set -euo pipefail

install_args=(--frozen-lockfile)
[[ ${BUN_INSTALL_OFFLINE:-0} == "1" ]] && install_args+=(--offline)
bun install "${install_args[@]}"

echo "✅ Repository setup complete"
