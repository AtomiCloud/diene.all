#!/usr/bin/env bash
set -euo pipefail

# Restore declared packages first so skills-sync cannot publish a partial cache-derived vendor tree.
compgen -G '*.slnx' >/dev/null && echo "🔧 Restoring declared packages before vendoring their skills..." && dotnet restore >/dev/null

# Populate the Go module cache first so skills-sync cannot publish a partial vendor tree.
[ -f go.mod ] && echo "🔧 Downloading declared Go modules before vendoring their skills..." && go mod download

./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
