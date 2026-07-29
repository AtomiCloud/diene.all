#!/usr/bin/env bash
set -euo pipefail

packages="./lib/..."
# The testhelper package is optional: NO-verdict libraries ship none.
[ -d testhelper ] && packages="${packages} ./testhelper/..."
# The adapters tree only exists for libraries that bind infrastructure.
[ -d adapters ] && packages="${packages} ./adapters/..."

# shellcheck disable=SC2086 # intentional word splitting of the package list
go test -run '^$' ${packages}

echo "✅ Go source packages typecheck"
