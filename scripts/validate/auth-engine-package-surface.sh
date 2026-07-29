#!/usr/bin/env bash
set -euo pipefail

artifacts="${1:-artifacts/package}"
version="${2:-$(xmlstarlet sel -t -v '/Project/PropertyGroup/Version' Version.props)}"
main_id="AtomiCloud.Diene.AuthEngine"
helper_id="AtomiCloud.Diene.AuthEngine.TestHelper"
main_package="${artifacts}/${main_id}.${version}.nupkg"
helper_package="${artifacts}/${helper_id}.${version}.nupkg"
main_entry="lib/net10.0/${main_id}.dll"
helper_entry="lib/net10.0/${helper_id}.dll"

command -v unzip >/dev/null || {
  echo "❌ unzip is required for managed surface validation" >&2
  exit 2
}
command -v dotnet >/dev/null || {
  echo "❌ dotnet is required for managed surface validation" >&2
  exit 2
}
test -s "${main_package}" || {
  echo "❌ main package is missing: ${main_package}" >&2
  exit 3
}
test -s "${helper_package}" || {
  echo "❌ TestHelper package is missing: ${helper_package}" >&2
  exit 3
}

scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

extract_dll() {
  local package="$1"
  local entry="$2"
  local destination="$3"

  unzip -Z1 "${package}" | rg -Fxq "${entry}" || {
    echo "❌ ${package} does not contain ${entry}" >&2
    exit 4
  }
  unzip -p "${package}" "${entry}" >"${destination}"
  test -s "${destination}" || {
    echo "❌ extracted DLL is empty: ${destination}" >&2
    exit 4
  }
}

extract_dll "${main_package}" "${main_entry}" "${scratch}/main.dll"
extract_dll "${helper_package}" "${helper_entry}" "${scratch}/helper.dll"

echo "🔬 Positive-controlling and verifying packaged managed surfaces..."
dotnet run --project tools/ManagedSurfaceInspector/ManagedSurfaceInspector.csproj \
  --configuration Release -- \
  verify "${scratch}/main.dll" tools/ManagedSurfaceInspector/auth-engine.json
dotnet run --project tools/ManagedSurfaceInspector/ManagedSurfaceInspector.csproj \
  --configuration Release --no-build -- \
  verify "${scratch}/helper.dll" tools/ManagedSurfaceInspector/testhelper.json

echo "🛣️  Restoring the packed library into the route probe..."
restore_sources="$(pwd)/${artifacts};https://api.nuget.org/v3/index.json"
dotnet restore tools/PackageRouteProbe/PackageRouteProbe.csproj \
  -p:PackageUnderTestVersion="${version}" \
  -p:RestoreSources="${restore_sources}" >/dev/null
dotnet run --project tools/PackageRouteProbe/PackageRouteProbe.csproj \
  --configuration Release --no-restore \
  -p:PackageUnderTestVersion="${version}"

echo "✅ Packaged public surfaces and one-call route mapping are complete"
