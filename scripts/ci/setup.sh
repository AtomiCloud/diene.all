#!/usr/bin/env bash
set -euo pipefail

# ### go-base
# #### source: go-base
go mod download

# skills-sync regenerates the vendored dependency-skill tree from the RESOLVED
# module directory of every dependency, so the Go dependencies must be
# downloaded first. On a cold module cache `go list -m -json all` reports a
# dependency with no ".Dir" — the module graph is known, the module content is
# not — and the regenerator correctly fails closed rather than vendoring a
# partial tree. Resolving first is what makes that fail-closed check unreachable
# on the normal path.
./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
