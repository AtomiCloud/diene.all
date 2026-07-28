using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Module;
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
        AuthEngineDemo.Describe(outcome).Should()
            .StartWith("authorized user-1 with scopes [notes:read]")
            .And.Contain($"issuer {Issuer}");
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
    public async Task Exercises_the_client_and_onboarding_surface_end_to_end()
    {
        using var issuer = new TestTokenIssuer(Issuer);
        var config = AuthEngineDemo.BuildConfig(Issuer, Endpoint).Get();
        var clock = new FakeAuthClock(Now);
        var validator = new JwtTokenValidator(config, issuer.KeyResolver, clock);
        var backend = new FakeOnboardingBackend("demo-backend");
        var client = new FakeCredentialClient { RotatedRefreshToken = "rt-2" };

        AuthEngineDemo.DescribeBackend(backend).Should().Contain("demo-backend");
        (await AuthEngineDemo.BackendKnows(backend, "user-1")).Get().Should().BeFalse();

        var token = issuer.MintValidFor("user-1", "https://api.test.invalid", Now, TimeSpan.FromMinutes(10), ["notes:read"]);
        var claims = (await validator.ValidateAsync(
            token,
            "https://api.test.invalid",
            TestContext.Current.CancellationToken)).Get();

        AuthEngineDemo.Describe(
                AtomiCloud.Diene.Results.Result.Ok<AuthClaims, AtomiCloud.Diene.Problems.IDomainProblem>(claims))
            .Should().Contain("authorized user-1").And.Contain(Issuer);

        (await AuthEngineDemo.GuardAnyScope(validator, token, "https://api.test.invalid", "notes:read"))
            .IsSuccess().Should().BeTrue();

        (await AuthEngineDemo.CompleteOnboarding(config, backend, claims, "lapras")).IsSuccess().Should().BeTrue();
        backend.WrittenLandscapes["user-1"].Should().Be("lapras");
        (await AuthEngineDemo.BackendKnows(backend, "user-1")).Get().Should().BeTrue();

        client.ScriptToken("https://api.test.invalid", "at-2", Now.AddMinutes(10));
        var refreshed = (await AuthEngineDemo.Refresh(client, "rt-1", "https://api.test.invalid")).Get();
        AuthEngineDemo.DescribeRefresh(refreshed).Should().Contain("rt-2");

        (await AuthEngineDemo.RevokeSessions(client, "user-1")).IsSuccess().Should().BeTrue();
        client.RevokedUsers.Should().BeEquivalentTo(["user-1"]);

        var cache = new TokenCache(client, clock, config.Lifetimes);
        await cache.GetAsync("https://api.test.invalid", cancellationToken: TestContext.Current.CancellationToken);
        AuthEngineDemo.ClearCachedTokens(cache);

        AuthEngineDemo.DescribeSession(new SessionView("user-1", ["notes:read"], Now.AddMinutes(10)))
            .Should().Contain("session user-1");

        AuthEngineDemo.DescribeOnboarding(OnboardingPhase.Complete).Should().Contain("complete");
        AuthEngineDemo.DescribeOnboarding(OnboardingPhase.AwaitingSync).Should().Contain("awaiting");
        AuthEngineDemo.DescribeOnboarding((OnboardingPhase)99).Should().Contain("unrecognised");
        AuthEngineDemo.DescribeLifetimes(config).Should().Contain("rotating True");
    }

    [Fact]
    public async Task Program_runs_the_whole_surface_and_enables_the_module()
    {
        var original = Console.Out;
        using var captured = new StringWriter();
        int exit;
        try
        {
            Console.SetOut(captured);
            exit = await Program.Main([]);
        }
        finally
        {
            Console.SetOut(original);
        }

        exit.Should().Be(0);

        var output = captured.ToString();
        output.Should().Contain("auth engine ready");
        output.Should().Contain("/app-handoff");
        output.Should().Contain("lifetimes: access");
        output.Should().Contain("onboarding: show the landscape selector");
        output.Should().Contain("module enabled");
    }

    [Fact]
    public async Task Program_reports_a_rejected_configuration_and_exits_non_zero()
    {
        // The failure path must be visible AND distinguishable: a bad issuer names the
        // field and returns 1 rather than printing a ready line and exiting 0.
        var original = Console.Out;
        var issuer = Environment.GetEnvironmentVariable("AUTH_ISSUER");
        using var captured = new StringWriter();
        int exit;
        try
        {
            Console.SetOut(captured);
            Environment.SetEnvironmentVariable("AUTH_ISSUER", "not-a-uri");
            exit = await Program.Main([]);
        }
        finally
        {
            Environment.SetEnvironmentVariable("AUTH_ISSUER", issuer);
            Console.SetOut(original);
        }

        exit.Should().Be(1);
        captured.ToString().Should().Contain("configuration rejected").And.Contain("logto.issuer");
    }
}
