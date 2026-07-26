#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh

version="$(xmlstarlet sel -t -v '/Project/PropertyGroup/Version' Version.props)"
artifacts="artifacts/package"

rm -rf "${artifacts}"
mkdir -p "${artifacts}"

echo "📦 Packing the library at ${version}..."
dotnet pack dotnet-base.slnx -c Release --output "${artifacts}"

./scripts/validate/dotnet-package.sh inventory "${artifacts}" "${version}"
./scripts/validate/dotnet-package.sh metadata "${artifacts}" "${version}"
./scripts/validate/dotnet-package.sh symbols "${artifacts}" "${version}"

scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

echo "🧪 Restoring the package into a scratch consumer..."
dotnet new console --framework net10.0 --no-restore --output "${scratch}" >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.CoreUtils --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
printf '%s\n' \
  'using System.Text.Json;' \
  'using AtomiCloud.Diene.CoreUtils;' \
  'using AtomiCloud.Diene.CoreUtils.Json;' \
  '' \
  'if (Slug.NamespacedKey("AtomiCloud", "Express Parcel").Get() != "atomicloud:express-parcel") return 1;' \
  'if (!KeyNormalizer.KeysMatch("error_portal", "ErrorPortal")) return 1;' \
  'if (Wire.Format(Wire.ParseDuration("PT1M30S").Get()) != "PT1M30S") return 1;' \
  'if (JsonSerializer.Serialize(new DateOnly(2026, 7, 25), AtomiJson.DefaultOptions) != "\"2026-07-25\"") return 1;' \
  'return 0;' >"${scratch}/Program.cs"
dotnet restore "${scratch}" --source "$(pwd)/${artifacts}" --source https://api.nuget.org/v3/index.json >/dev/null
dotnet build "${scratch}" -c Release --no-restore >/dev/null

echo "✅ Package validation and scratch consumption passed"
