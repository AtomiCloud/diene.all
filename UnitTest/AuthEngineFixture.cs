using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.TestHelper.Builders;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;

namespace AtomiCloud.DotnetBase.UnitTest;

/// <summary>
/// Shared construction for the suite. Every test drives the same fixed clock and the same
/// issuer, so a failure is about the case under test rather than about which instant the
/// machine happened to be at.
/// </summary>
internal static class AuthEngineFixture
{
    internal const string Issuer = "https://idp.test.invalid/oidc";
    internal const string Audience = "https://api.test.invalid";
    internal const string Subject = "user-1";

    internal static readonly DateTimeOffset Now = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);

    internal static AuthEngineConfig Config(string homeClaim = "home_landscape")
    {
        var management = LogtoManagementConfig.Create(
            "https://idp.test.invalid",
            "https://idp.test.invalid/api",
            "management-client",
            "management-secret").Get();

        var logto = LogtoConfig.Create(
            "https://idp.test.invalid",
            Issuer,
            "app",
            "app-secret",
            management).Get();

        return AuthEngineConfig.Create(
            logto,
            HandoffConfig.Default,
            TokenLifetimeConfig.Default,
            homeClaim).Get();
    }

    internal static TestTokenIssuer NewIssuer() => new(Issuer);

    internal static FakeAuthClock Clock() => new(Now);

    internal static JwtTokenValidator Validator(
        TestTokenIssuer issuer,
        IAuthClock clock,
        AuthEngineConfig? config = null) =>
        new(config ?? Config(), issuer.KeyResolver, clock);
}
