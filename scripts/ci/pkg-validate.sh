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
dotnet add "${scratch}" package AtomiCloud.Diene.StandardConfig --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.StandardConfig.TestHelper --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
printf '%s\n' \
  'using AtomiCloud.Diene.StandardConfig.Presets;' \
  'using AtomiCloud.Diene.StandardConfig.Storage;' \
  'using AtomiCloud.Diene.StandardConfig.TestHelper;' \
  'using AtomiCloud.Diene.StandardConfig.TestHelper.Storage;' \
  '' \
  '// The shipped surface: the four frozen block keys and a keyed lookup.' \
  'if (PostgresOption.Key != "Postgres" || StorageOption.Key != "Storage") return 1;' \
  'var block = new CacheBlock { ["main"] = new CacheOption { Host = "localhost", Port = 6379 } };' \
  'if (block.Named("MAIN").Port != 6379) return 1;' \
  '' \
  '// The TestHelper surface: the in-memory fake and the preset assertions.' \
  'IBlockStorage storage = new InMemoryBlockStorage();' \
  'var saved = await storage.SaveAsync(new SaveInput { Key = "a.txt", Body = new byte[] { 1 } });' \
  'if (!saved.IsSuccess(out var stored) || stored.Link != storage.GetLink("a.txt")) return 1;' \
  'block.ShouldAsPresetBlock().HaveConnection("MAIN").And.Subject.ShouldAsPresetBlock()' \
  '    .BeValidAgainst(new CacheBlockValidator());' \
  'return 0;' >"${scratch}/Program.cs"
dotnet restore "${scratch}" --source "$(pwd)/${artifacts}" --source https://api.nuget.org/v3/index.json >/dev/null
dotnet build "${scratch}" -c Release --no-restore >/dev/null

echo "✅ Package validation and scratch consumption passed"
