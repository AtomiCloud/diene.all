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
./scripts/validate/auth-engine-package-surface.sh "${artifacts}" "${version}"
./scripts/validate/dotnet-package.sh metadata "${artifacts}" "${version}"
./scripts/validate/dotnet-package.sh symbols "${artifacts}" "${version}"

scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

echo "🧪 Restoring both packages into a scratch consumer..."
dotnet new console --framework net10.0 --no-restore --output "${scratch}" >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.AuthEngine --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.AuthEngine.TestHelper --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null

# Exercises BOTH packages through the surface a real consumer uses: build config,
# mint a signed token against the fake issuer, validate it, and assert on the
# result. A restore-only check would prove the packages resolve while saying
# nothing about whether their public API is usable together.
printf '%s\n' \
  'using AtomiCloud.Diene.AuthEngine.Config;' \
  'using AtomiCloud.Diene.AuthEngine.Policy;' \
  'using AtomiCloud.Diene.AuthEngine.TestHelper.Assertions;' \
  'using AtomiCloud.Diene.AuthEngine.TestHelper.Builders;' \
  'using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;' \
  'using AtomiCloud.Diene.AuthEngine.Tokens;' \
  '' \
  'const string issuerUri = "https://idp.example.test/oidc";' \
  'const string audience = "https://api.example.test";' \
  '' \
  'var management = LogtoManagementConfig' \
  '    .Create("https://idp.example.test", "https://idp.example.test/api", "mgmt", "secret")' \
  '    .Get();' \
  'var logto = LogtoConfig' \
  '    .Create("https://idp.example.test", issuerUri, "app", "secret", management)' \
  '    .Get();' \
  'var config = AuthEngineConfig' \
  '    .Create(logto, HandoffConfig.Default, TokenLifetimeConfig.Default, "home_landscape")' \
  '    .Get();' \
  '' \
  'var now = new DateTimeOffset(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);' \
  'using var issuer = new TestTokenIssuer(issuerUri);' \
  'var validator = new JwtTokenValidator(config, issuer.KeyResolver, new FakeAuthClock(now));' \
  '' \
  'var token = issuer.MintValidFor("user-1", audience, now, TimeSpan.FromMinutes(10), ["notes:read"]);' \
  'var guard = new AuthGuard(validator);' \
  'var outcome = await guard.GuardAsync(token, audience, [new RequireAllScopes("notes:read")]);' \
  '' \
  'outcome.ShouldBeAuthorized().ShouldHaveSubject("user-1").ShouldGrantScopes("notes:read");' \
  'Console.WriteLine("scratch consumer validated the auth engine surface");' >"${scratch}/Program.cs"

# nuget.org is listed so the scratch consumer can resolve the TRANSITIVE published
# Diene dependencies; the node's OWN ids still come from the local artifacts source.
dotnet restore "${scratch}" \
  --source "$(pwd)/${artifacts}" \
  --source https://api.nuget.org/v3/index.json >/dev/null
dotnet build "${scratch}" -c Release --no-restore >/dev/null

echo "✅ Package validation and scratch consumption passed"
