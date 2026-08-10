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
dotnet add "${scratch}" package AtomiCloud.Diene.ApiEngine --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.ApiEngine.TestHelper --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null

# Exercises BOTH packages through the surface a real consumer uses: validate an upstream
# block, wrap a call through the engine's own handler pipeline, and assert on the classified
# outcome. A restore-only check would prove the packages resolve while saying nothing about
# whether their public API is usable together — and this pair is only useful together.
printf '%s\n' \
  'using System.Net;' \
  'using AtomiCloud.Diene.ApiEngine.Calls;' \
  'using AtomiCloud.Diene.ApiEngine.Client;' \
  'using AtomiCloud.Diene.ApiEngine.Config;' \
  'using AtomiCloud.Diene.ApiEngine.TestHelper.Assertions;' \
  'using AtomiCloud.Diene.ApiEngine.TestHelper.Builders;' \
  'using AtomiCloud.Diene.ApiEngine.TestHelper.Fakes;' \
  'using AtomiCloud.Diene.ApiEngine.Transport;' \
  'using AtomiCloud.Diene.Problems;' \
  '' \
  'var address = ServiceAddress.Create("lithium", "notes", "note").Get();' \
  'var option = new HttpClientOption { BaseAddress = "https://notes.example.test/", Timeout = "PT5S" };' \
  'var config = ApiEngineConfig' \
  '    .Create(new Dictionary<string, HttpClientOption>(StringComparer.Ordinal) { [address.ToString()] = option })' \
  '    .Get();' \
  '' \
  'var portal = new ErrorPortalConfig("https", "errors.example.test",' \
  '    new ProblemIdentity("lapras", "lithium", "notes", "note"));' \
  'var caller = new ApiCaller(config, new ProblemTypeUriBuilder(portal));' \
  '' \
  'var upstream = new FakeUpstream("notes");' \
  'upstream.RespondJson(HttpStatusCode.BadRequest, UpstreamResponses.NonProblemJson("legacy contract", 4001));' \
  '' \
  'using var http = new HttpClient(' \
  '    new RetryOnceHandler { InnerHandler = new FailureCaptureHandler { InnerHandler = upstream } })' \
  '    { BaseAddress = option.BaseAddress is null ? null : new Uri(option.BaseAddress) };' \
  '' \
  'var outcome = await caller.Call(address, async token =>' \
  '{' \
  '    using var response = await http.GetAsync("/notes/1", token);' \
  '    response.EnsureSuccessStatusCode();' \
  '    return 1;' \
  '});' \
  '' \
  'var payload = outcome.ShouldBeUpstreamRejected();' \
  'if (payload.UpstreamStatus != 400) throw new InvalidOperationException($"expected 400, got {payload.UpstreamStatus}");' \
  'if (upstream.Attempts != 1) throw new InvalidOperationException($"expected 1 attempt, got {upstream.Attempts}");' \
  'Console.WriteLine("scratch consumer classified an upstream rejection through the shipped pipeline");' >"${scratch}/Program.cs"

# nuget.org is listed so the scratch consumer can resolve the TRANSITIVE published Diene
# dependencies; the node's OWN ids still come from the local artifacts source.
dotnet restore "${scratch}" \
  --source "$(pwd)/${artifacts}" \
  --source https://api.nuget.org/v3/index.json >/dev/null
dotnet build "${scratch}" -c Release --no-restore >/dev/null

# Run it, rather than only compiling it. A consumer that builds proves the API is
# reference-compatible; only executing it proves the two packages behave together — and the
# assertions above are what make a wrong classification a non-zero exit rather than a log line.
dotnet run --project "${scratch}" -c Release --no-build

echo "✅ Package validation and scratch consumption passed"
