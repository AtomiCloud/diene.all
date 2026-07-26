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
dotnet add "${scratch}" package AtomiCloud.Diene.Problems --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.Problems.TestHelper --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
printf '%s\n' \
  'using AtomiCloud.Diene.Problems;' \
  'using AtomiCloud.Diene.Problems.Catalog;' \
  'using AtomiCloud.Diene.Problems.TestHelper;' \
  'using FluentAssertions;' \
  '' \
  'var identity = new ProblemIdentity("raichu", "dotnet", "notes", "api");' \
  'var typeUris = new ProblemTypeUriBuilder(new ErrorPortalConfig("https", "docs.example.test", identity));' \
  'var catalog = new ProblemCatalogBuilder().AddBaseline().Build();' \
  'IDomainProblem problem = new EntityNotFound("missing", typeof(string), "note-42");' \
  'problem.Should().BeProblem<EntityNotFound>();' \
  'problem.Should().HaveId("entity_not_found");' \
  'catalog.StatusOf(problem).Should().Be(404);' \
  'typeUris.Build(problem.Version, problem.Id).AbsoluteUri.Should().EndWith("/v1/entity_not_found");' >"${scratch}/Program.cs"
dotnet restore "${scratch}" \
  --source "$(pwd)/${artifacts}" \
  --source https://api.nuget.org/v3/index.json >/dev/null
dotnet build "${scratch}" -c Release --no-restore >/dev/null

echo "✅ Package validation and scratch consumption passed"
