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
dotnet add "${scratch}" package AtomiCloud.Diene.Otel --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.Otel.TestHelper --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
printf '%s\n' \
  'using AtomiCloud.Diene.Otel;' \
  'using AtomiCloud.Diene.Otel.TestHelper;' \
  '' \
  'var identity = AppIdentity.Create("lapras", "atomi", "scratch", "consumer", "1.0.0").Get();' \
  'using var instrumentation = new Instrumentation(identity);' \
  'var emitter = new InMemoryTraceEmitter();' \
  'var record = TraceRecord.Create("scratch.span", status: TraceStatus.Ok).Get();' \
  'emitter.Emit(record);' \
  'Console.WriteLine(AtomiResource.Map(identity)[AtomiResource.ServiceNameKey]);' \
  'Console.WriteLine(emitter.Records.Count);' >"${scratch}/Program.cs"
dotnet restore "${scratch}" --source "$(pwd)/${artifacts}" >/dev/null
dotnet build "${scratch}" -c Release --no-restore >/dev/null

echo "✅ Package validation and scratch consumption passed"
