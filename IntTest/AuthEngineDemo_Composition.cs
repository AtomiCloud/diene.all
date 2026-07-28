using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Onboarding;
using AtomiCloud.Diene.AuthEngine.TestHelper.Builders;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.DotnetBase.App;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.IntTest;

/// <summary>
/// Exercises the demo consumer end to end: the composition a real service performs,
/// driven through the shipped fakes rather than a live identity provider.
/// </summary>
public class AuthEngineDemo_Composition
{
    private const string Issuer = "https://idp.test.invalid/oidc";
    private const string Endpoint = "https://idp.test.invalid";
    private static readonly DateTimeOffset Now = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void BuildConfig_composes_a_valid_configuration()
    {
        var config = AuthEngineDemo.BuildConfig(Issuer, Endpoint).Get();

        config.Logto.Issuer.Should().Be(Issuer);
        config.Handoff.Mount.Should().Be(HandoffConfig.DefaultMount);
        config.Lifetimes.Access.Should().Be(TimeSpan.FromMinutes(10));
    }

    [Theory]
    [InlineData("not-a-uri", Endpoint)]
    [InlineData(Issuer, "not-a-uri")]
    public void BuildConfig_reports_the_offending_field_rather_than_throwing(string issuer, string endpoint)
    {
        var config = AuthEngineDemo.BuildConfig(issuer, endpoint);

        config.IsFailure().Should().BeTrue();
        config.GetFailure().Field.Should().StartWith("logto");
    }

    [Fact]
    public async Task GuardRequest_admits_a_caller_satisfying_scopes_and_landscape()
    {
        using var issuer = new TestTokenIssuer(Issuer);
        var config = AuthEngineDemo.BuildConfig(Issuer, Endpoint).Get();
        var validator = new JwtTokenValidator(config, issuer.KeyResolver, new FakeAuthClock(Now));

        var token = issuer.MintValidFor(
            "user-1",
            "https://api.test.invalid",
            Now,
            TimeSpan.FromMinutes(10),
            ["notes:read"],
            new Dictionary<string, object> { ["home_landscape"] = "lapras" });

        var outcome = await AuthEngineDemo.GuardRequest(
            validator,
            config,
            token,
            "https://api.test.invalid",
            "lapras",
            "notes:read");

        outcome.IsSuccess().Should().BeTrue();
        AuthEngineDemo.Describe(outcome).Should().Be("authorized user-1 with scopes [notes:read]");
    }

    [Fact]
    public async Task GuardRequest_refuses_and_renders_the_reason()
    {
        using var issuer = new TestTokenIssuer(Issuer);
        var config = AuthEngineDemo.BuildConfig(Issuer, Endpoint).Get();
        var validator = new JwtTokenValidator(config, issuer.KeyResolver, new FakeAuthClock(Now));

        var token = issuer.MintValidFor("user-1", "https://api.test.invalid", Now, TimeSpan.FromMinutes(10));

        var outcome = await AuthEngineDemo.GuardRequest(
            validator,
            config,
            token,
            "https://api.test.invalid",
            "lapras",
            "notes:read");

        outcome.IsFailure().Should().BeTrue();
        AuthEngineDemo.Describe(outcome).Should().StartWith("refused (unauthorized):");
    }

    [Fact]
    public async Task AcquireServiceToken_returns_a_cached_token()
    {
        var client = new FakeCredentialClient();
        client.ScriptToken("https://api.test.invalid", "svc-1", Now.AddMinutes(10));
        var config = AuthEngineDemo.BuildConfig(Issuer, Endpoint).Get();

        var outcome = await AuthEngineDemo.AcquireServiceToken(
            client,
            new FakeAuthClock(Now),
            config,
            "https://api.test.invalid",
            "notes:read");

        outcome.Get().Token.Should().Be("svc-1");
    }

    [Fact]
    public async Task ResolveOnboarding_reports_the_phase_for_a_user_without_a_claim()
    {
        using var issuer = new TestTokenIssuer(Issuer);
        var config = AuthEngineDemo.BuildConfig(Issuer, Endpoint).Get();
        var validator = new JwtTokenValidator(config, issuer.KeyResolver, new FakeAuthClock(Now));

        var token = issuer.MintValidFor("user-1", "https://api.test.invalid", Now, TimeSpan.FromMinutes(10));
        var claims = (await validator.ValidateAsync(
            token,
            "https://api.test.invalid",
            TestContext.Current.CancellationToken)).Get();

        var phase = await AuthEngineDemo.ResolveOnboarding(config, new FakeOnboardingBackend(), claims);

        phase.Get().Should().Be(OnboardingPhase.SelectLandscape);
    }

    [Fact]
    public void Program_runs_and_reports_the_composed_configuration()
    {
        var original = Console.Out;
        using var captured = new StringWriter();
        try
        {
            Console.SetOut(captured);
            Program.Main();
        }
        finally
        {
            Console.SetOut(original);
        }

        captured.ToString().Should().Contain("auth engine ready").And.Contain("/app-handoff");
    }
}
