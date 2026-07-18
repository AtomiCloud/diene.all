#!/usr/bin/env bash
set -euo pipefail

echo "🔧 Restoring repo-local .NET tools..."
dotnet tool restore

echo "✅ .NET setup complete"
