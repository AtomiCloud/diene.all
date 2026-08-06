#!/usr/bin/env bash
set -euo pipefail

echo "🔨 Building the .NET solution in Release..."
dotnet build ./*.slnx -c Release

echo "✅ .NET build complete"
