#!/usr/bin/env bash
set -euo pipefail

packages="./lib/..."
# The testhelper package is optional: NO-verdict libraries (core-utils) ship none.
[ -d testhelper ] && packages="${packages} ./testhelper/..."

# shellcheck disable=SC2086 # intentional word splitting of the package list
go test -run '^$' ${packages}

echo "✅ Go source packages typecheck"
