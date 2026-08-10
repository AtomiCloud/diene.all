#!/usr/bin/env bash
set -euo pipefail

# ### dotnet-server-engine-setup-restore
# #### source: lib/dotnet/server-engine
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

# ### workspace-setup
# #### source: workspace
releaser conventions -c release.yaml
skills-sync sync --tier setup

# ### dotnet-base-setup
# #### source: dotnet-base
./scripts/local/setup.sh

# ### workspace-setup-complete
# #### source: workspace
echo "✅ Repository setup complete"
