#!/usr/bin/env bash
set -euo pipefail

# The declared NuGet packages are restored BEFORE skills are synchronized.
# skills-sync vendors from ${HOME}/.nuget/packages, so on a runner whose shared
# cache holds only SOME of the declared skill-bearing packages it publishes a
# PARTIAL vendor tree — and the freshness gate then fails three steps later on a
# diff that says nothing about the cause. Restoring first makes the vendor tree a
# function of the declared dependency set instead of ambient cache state.
if compgen -G '*.slnx' >/dev/null; then
  echo "🔧 Restoring declared packages before vendoring their skills..."
  dotnet restore >/dev/null
fi

./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
