#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh

version="$(xmlstarlet sel -t -v '/Project/PropertyGroup/Version' Version.props)"
artifacts="artifacts/package"

rm -rf "${artifacts}"
mkdir -p "${artifacts}"

echo "📦 Packing library and TestHelper at ${version}..."
dotnet pack dotnet-base.slnx -c Release --output "${artifacts}"

./scripts/validate/dotnet-package.sh inventory "${artifacts}" "${version}"
./scripts/validate/dotnet-package.sh metadata "${artifacts}" "${version}"
./scripts/validate/dotnet-package.sh symbols "${artifacts}" "${version}"

scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

echo "🧪 Restoring both packages into a scratch consumer..."
dotnet new console --framework net10.0 --no-restore --output "${scratch}" >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.Config --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.Config.TestHelper --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
printf '%s\n' \
  'using AtomiCloud.Diene.Config;' \
  'using AtomiCloud.Diene.Config.TestHelper;' \
  '' \
  '// The shipped surface: canonical keys and the service-tree block.' \
  'if (ConfigKey.Path("Error_Portal:Host") != "errorportal:host") return 1;' \
  'if (AppOption.Key != "App") return 1;' \
  '' \
  '// The TestHelper surface: three fake layers in real precedence order.' \
  'var config = new AtomiConfigFixture()' \
  '    .WithBase("error_portal:host", "base")' \
  '    .WithLandscape("error_portal:host", "landscape")' \
  '    .WithEnvironment("ERROR_PORTAL__HOST", "environment")' \
  '    .Build();' \
  'if (config["errorportal:host"] != "environment") return 1;' \
  'config.Should().HaveValue("error_portal:host", "environment");' \
  'return 0;' >"${scratch}/Program.cs"
dotnet restore "${scratch}" --source "$(pwd)/${artifacts}" --source https://api.nuget.org/v3/index.json >/dev/null
dotnet build "${scratch}" -c Release --no-restore >/dev/null

echo "✅ Package validation and scratch consumption passed"
