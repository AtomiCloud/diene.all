#!/usr/bin/env bash
set -euo pipefail

# The image is built in the external fork, so this repository can only prove
# install wiring here. The live runner installs the Garden-local chart after
# Garden has created its database and LogtoInstance boot Secrets.
proof="scripts/validate/lithium-k3d.sh"
test -x "${proof}"
rg -q 'K3D_ISOLATE_BY_PATH=true is mandatory' "${proof}"
rg -q 'helm upgrade --install lithium chart' "${proof}"
rg -q -- '--values chart/values.lapras.yaml' "${proof}"
rg -q 'get service lithium-management' "${proof}"
if rg -q 'primordial-chart' "${proof}"; then
  echo "❌ Garden-local proof must not install the primordial chart" >&2
  exit 1
fi
echo "✅ Lithium k3d Garden-local install contract passed"
