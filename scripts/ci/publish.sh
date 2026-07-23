#!/usr/bin/env bash
set -euo pipefail

./scripts/validate/dotnet-publish.sh

version="${GITHUB_REF_NAME#v}"
[ -z "${NUGET_API_KEY:-}" ] && echo "❌ NUGET_API_KEY must be set from the org secret" >&2 && exit 1

./scripts/ci/setup.sh

artifacts="artifacts/publish"
rm -rf "${artifacts}"
mkdir -p "${artifacts}"

echo "📦 Packing release ${version}..."
dotnet pack dotnet-base.slnx -c Release --output "${artifacts}"
./scripts/validate/dotnet-package.sh inventory "${artifacts}" "${version}"

echo "🚀 Publishing packages and symbols with skip-duplicate..."
for package in "${artifacts}"/*.nupkg "${artifacts}"/*.snupkg; do
  dotnet nuget push "${package}" --api-key "${NUGET_API_KEY}" --source https://api.nuget.org/v3/index.json --skip-duplicate
done

echo "✅ Published both NuGet packages and symbol packages at ${version}"
