#!/usr/bin/env bash
set -euo pipefail

# Smoke-test one standalone binary: run --version/--help and assert the help banner names the CLI.
bin="${1:?Usage: smoke.sh <path-to-binary>}"
[[ ! -x ${bin} ]] && echo "❌ compiled artifact is not executable: ${bin}" >&2 && exit 1

# The CLI's own name comes from package.json .bin — never assert on a sample command.
name="$(jq -r '.bin | to_entries[0].key' package.json)"
[ -z "${name}" ] && echo "❌ no .bin entry in package.json" >&2 && exit 1
[ "${name}" = "null" ] && echo "❌ no .bin entry in package.json" >&2 && exit 1

"${bin}" --version
help="$("${bin}" --help)"
printf '%s\n' "${help}"

! grep -q 'Usage:' <<<"${help}" && echo "❌ --help is missing its usage banner" >&2 && exit 1
! grep -q "${name}" <<<"${help}" && echo "❌ --help does not name '${name}'" >&2 && exit 1

# Exercise a real operation, not just banners: lint a valid conventional-commit
# message through the compiled binary against the repository's own config.
msg_file="$(mktemp)"
trap 'rm -f "${msg_file}"' EXIT
printf '%s\n' 'feat: add a release capability' >"${msg_file}"
"${bin}" lint-commit "${msg_file}" -c atomi_release.yaml
echo "✅ lint-commit ok"

echo "✅ smoke ok: ${bin}"
