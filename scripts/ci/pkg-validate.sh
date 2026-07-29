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
dotnet add "${scratch}" package AtomiCloud.Diene.E2e --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.E2e.TestHelper --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
printf '%s\n' \
  'using System.Net;' \
  'using AtomiCloud.Diene.E2e;' \
  'using AtomiCloud.Diene.E2e.Drivers;' \
  'using AtomiCloud.Diene.E2e.Garden;' \
  'using AtomiCloud.Diene.E2e.TestHelper.Assertions;' \
  '' \
  'var fixture = new GardenNamespaceFixture(' \
  '    "api", "notes", "sulfoxide", "pichu", "mew", "cluster.atomi.cloud");' \
  'var endpoint = GardenPreviewEndpoint.Resolve(fixture.Hostname, fixture);' \
  'await using var driver = new GardenSitDriver(endpoint, new StubHandler());' \
  'using var response = await driver.Client.GetAsync("/system/health");' \
  'response.ShouldHaveStatus(HttpStatusCode.NoContent);' \
  'if (PublishedPackageBundle.RuntimeAssemblyNames.Count != 10) throw new InvalidOperationException();' \
  'if (PublishedPackageBundle.TestHelperAssemblyNames.Count != 9) throw new InvalidOperationException();' \
  'Console.WriteLine("scratch consumer drove the shipped Garden and assertion surface");' \
  '' \
  'sealed class StubHandler : HttpMessageHandler' \
  '{' \
  '    protected override Task<HttpResponseMessage> SendAsync(' \
  '        HttpRequestMessage request, CancellationToken cancellationToken) =>' \
  '        Task.FromResult(new HttpResponseMessage(HttpStatusCode.NoContent));' \
  '}' >"${scratch}/Program.cs"
dotnet restore "${scratch}" \
  --source "$(pwd)/${artifacts}" \
  --source https://api.nuget.org/v3/index.json >/dev/null
dotnet build "${scratch}" -c Release --no-restore >/dev/null
dotnet run --project "${scratch}" -c Release --no-build

echo "✅ Package validation and scratch consumption passed"
