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
dotnet add "${scratch}" package AtomiCloud.Diene.ServerEngine --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.ServerEngine.TestHelper --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null

# The scratch consumer RUNS rather than only compiling. A build proves the public
# surface resolves; it does not prove the shipped assembly composes a host, mounts
# its routes, or verifies a signature — and those are what a consumer installs the
# package for. The exit code carries the verdict.
cat >"${scratch}/Program.cs" <<'CONSUMER'
using AtomiCloud.Diene.ServerEngine.Config;
using AtomiCloud.Diene.ServerEngine.TestHelper.Assertions;
using AtomiCloud.Diene.ServerEngine.TestHelper.Builders;
using AtomiCloud.Diene.ServerEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;

var identity = ServiceIdentityConfig.Create("lapras", "sulfoxide", "scratch", "api", "1.0.0");
if (identity.IsFailure(out var identityError)) throw new InvalidOperationException(identityError.ToString());

var config = ServerEngineConfig.Create(identity.Get(), WebhookConfig.Default);
if (config.IsFailure(out var configError)) throw new InvalidOperationException(configError.ToString());

await using var host = await ServerEngineTestHost.StartAsync(options =>
    options.Handlers.Add(new RecordingWebhookHandler("stripe")));

using var version = await host.Client.GetAsync("/system/version");
version.EnsureSuccessStatusCode();

var body = new WebhookEnvelopeBuilder().ToBytes();
(await host.DeliverAsync("stripe", body)).ShouldBeProcessed();
(await host.DeliverAsync("stripe", body, key: "the-wrong-secret")).ShouldBeSignatureRejected();
(await host.DeliverAsync("paypal", new WebhookEnvelopeBuilder("paypal").ToBytes())).ShouldBeNotMine();

Console.WriteLine($"scratch consumer verified {config.Get().Identity.Service} at {config.Get().Identity.Version}");
CONSUMER

# Both the local artifact folder AND nuget.org are supplied. The packages under test
# depend on published Diene packages, so a local-only source cannot resolve the
# transitive graph — and a restore that cannot resolve it fails rather than proving
# anything about these two packages.
dotnet restore "${scratch}" --source "$(pwd)/${artifacts}" --source https://api.nuget.org/v3/index.json >/dev/null
dotnet build "${scratch}" -c Release --no-restore >/dev/null
dotnet run --project "${scratch}" -c Release --no-build --no-restore

echo "✅ Package validation and scratch consumption passed"
