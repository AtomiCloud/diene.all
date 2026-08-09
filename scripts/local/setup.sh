#!/usr/bin/env bash
set -euo pipefail

releaser conventions -c release.yaml
skills-sync sync

# ### dotnet-base-setup
# #### source: dotnet-base
echo "🔧 Restoring repo-local .NET tools..."
dotnet tool restore

echo "✅ setup completed"
