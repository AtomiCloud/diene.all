#!/usr/bin/env bash
set -euo pipefail

# Smoke-test one standalone binary: run --version/--help and assert the help banner names the CLI.
bin="${1:?Usage: smoke.sh <path-to-binary>}"
chmod +x "${bin}"
xattr -d com.apple.quarantine "${bin}" 2>/dev/null || true # mac-only; harmless elsewhere

# The CLI's own name comes from package.json .bin — never assert on a sample command.
name="$(jq -r '.bin | to_entries[0].key' package.json)"
[ -z "${name}" ] && echo "❌ no .bin entry in package.json" >&2 && exit 1
[ "${name}" = "null" ] && echo "❌ no .bin entry in package.json" >&2 && exit 1

"${bin}" --version
help="$("${bin}" --help)"
printf '%s\n' "${help}"

! grep -q 'Usage:' <<<"${help}" && echo "❌ --help is missing its usage banner" >&2 && exit 1
! grep -q "${name}" <<<"${help}" && echo "❌ --help does not name '${name}'" >&2 && exit 1

echo "✅ smoke ok: ${bin}"
