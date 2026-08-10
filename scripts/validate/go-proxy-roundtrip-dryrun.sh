#!/usr/bin/env bash
set -euo pipefail

# Compile and RUN the published-consumer payload of go-proxy-roundtrip.sh
# against the LOCAL module, before any tag exists.
#
# This exists because go-proxy-roundtrip.sh only ever runs against a real
# published tag: a compile error inside its heredoc passes branch CI and first
# surfaces as a red CD after the tag is pushed and can no longer be unpublished.
# Skipping this check cost a sibling library a forced patch release.
#
# It extracts the SAME heredoc the real script uses, so the two cannot drift,
# swaps the proxy dependency for the working tree with a throwaway replace
# directive, and asserts the identical expected output.

module="$(yq -r '.module' .config/go-lib.yaml)"
root="$(pwd)"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "${tmp}" 2>/dev/null || true; rm -rf "${tmp}"' EXIT

# Extract the heredoc body verbatim and expand only ${module}, exactly as the
# unquoted heredoc in the real script does.
awk '/^cat >main.go <<CONSUMER$/{capture=1; next} /^CONSUMER$/{capture=0} capture' \
  scripts/validate/go-proxy-roundtrip.sh |
  sed "s|\${module}|${module}|g" >"${tmp}/main.go"

[ ! -s "${tmp}/main.go" ] && echo "❌ could not extract the consumer payload" >&2 && exit 1

cd "${tmp}"
go mod init example.invalid/go-lib-consumer >/dev/null
# The replace directive is what makes this a DRY RUN: the published script has
# none, and a replace there would make the round trip vacuous.
go mod edit -require="${module}@v0.0.0" -replace="${module}=${root}"
go mod tidy
go build -o consumer .
got="$(./consumer)"
[ "${got}" != "true true true true true" ] &&
  echo "❌ consumer payload returned '${got}', want 'true true true true true'" >&2 && exit 1

echo "✅ the proxy round-trip consumer compiles and passes against the local module"
