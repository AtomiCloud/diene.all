using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Module;
using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.UnitTest.Module;

public class AuthEngineModule
{
    [Fact]
    public void Registers_the_whole_surface_so_a_host_can_resolve_it()
    {
        var services = new ServiceCollection();
        services.AddLogging();

        services.AddAtomiAuthEngine(AuthEngineFixture.Config());

        using var provider = services.BuildServiceProvider();
        provider.GetRequiredService<AuthEngineConfig>().Should().NotBeNull();
        provider.GetRequiredService<TokenLifetimeConfig>().Should().NotBeNull();
        provider.GetRequiredService<IAuthClock>().Should().BeOfType<SystemAuthClock>();
        provider.GetRequiredService<ITokenValidator>().Should().BeOfType<JwtTokenValidator>();
        provider.GetRequiredService<ISigningKeyResolver>().Should().BeOfType<OpenIdSigningKeyResolver>();
        provider.GetRequiredService<ICredentialClient>().Should().BeOfType<LogtoCredentialClient>();
        provider.GetRequiredService<AuthGuard>().Should().NotBeNull();
        provider.GetRequiredService<TokenCache>().Should().NotBeNull();
    }

    [Fact]
    public void Keeps_a_clock_the_consumer_already_registered()
    {
        // Overriding here would silently undo a test host's fixed clock, and the failure
        // would surface far from this line.
        var services = new ServiceCollection();
        services.AddLogging();
        var clock = new FakeAuthClock();
        services.AddSingleton<IAuthClock>(clock);

        services.AddAtomiAuthEngine(AuthEngineFixture.Config());

        using var provider = services.BuildServiceProvider();
        provider.GetRequiredService<IAuthClock>().Should().BeSameAs(clock);
    }

    [Fact]
    public void Resolves_the_system_clock_to_a_real_instant()
    {
        var before = DateTimeOffset.UtcNow;
        var now = SystemAuthClock.Instance.UtcNow;

        now.Should().BeOnOrAfter(before);
        SystemAuthClock.Instance.Should().BeSameAs(SystemAuthClock.Instance);
    }

    [Fact]
    public void Rejects_null_registration_arguments()
    {
        var services = new ServiceCollection();

        FluentActions.Invoking(() => services.AddAtomiAuthEngine(null!))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => AuthEngineServiceCollectionExtensions.AddAtomiAuthEngine(
                null!,
                AuthEngineFixture.Config()))
            .Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void ReadBearer_accepts_a_bearer_credential_case_insensitively()
    {
        var context = new DefaultHttpContext();
        context.Request.Headers.Authorization = "bearer abc123";

        AuthEngineEndpoints.ReadBearer(context.Request).Should().Be("abc123");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("Basic abc123")]
    [InlineData("Bearer ")]
    [InlineData("Bearer    ")]
    public void ReadBearer_returns_null_for_anything_that_is_not_a_bearer_token(string header)
    {
        var context = new DefaultHttpContext();
        context.Request.Headers.Authorization = header;

        AuthEngineEndpoints.ReadBearer(context.Request).Should().BeNull();
    }

    [Fact]
    public void ReadBearer_rejects_a_null_request() =>
        FluentActions.Invoking(() => AuthEngineEndpoints.ReadBearer(null!))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public async Task Session_endpoint_returns_the_validated_session_view()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock(), config));

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            config.Logto.Issuer,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            ["notes:read"]);

        var context = new DefaultHttpContext();
        context.Request.Headers.Authorization = $"Bearer {token}";

        var view = await AuthEngineEndpoints.HandleSessionAsync(context, guard, config);

        view.Subject.Should().Be(AuthEngineFixture.Subject);
        view.Scopes.Should().BeEquivalentTo(["notes:read"]);
        view.ExpiresAt.Should().Be(AuthEngineFixture.Now.AddMinutes(10));
    }

    [Fact]
    public async Task Session_endpoint_raises_the_typed_problem_when_the_header_is_absent()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock(), config));

        var exception = await FluentActions
            .Awaiting(() => AuthEngineEndpoints.HandleSessionAsync(new DefaultHttpContext(), guard, config))
            .Should().ThrowAsync<DomainProblemException>();

        exception.Which.Problem.Id.Should().Be("unauthenticated");
    }

    [Fact]
    public async Task Session_endpoint_raises_the_guards_problem_when_validation_fails()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config();
        var clock = AuthEngineFixture.Clock();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, clock, config));

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            config.Logto.Issuer,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        clock.Advance(TimeSpan.FromHours(1));

        var context = new DefaultHttpContext();
        context.Request.Headers.Authorization = $"Bearer {token}";

        var exception = await FluentActions
            .Awaiting(() => AuthEngineEndpoints.HandleSessionAsync(context, guard, config))
            .Should().ThrowAsync<DomainProblemException>();

        exception.Which.Problem.Detail.Should().Contain("expired");
    }

    [Fact]
    public async Task Session_endpoint_rejects_null_arguments()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock(), config));

        await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleSessionAsync(null!, guard, config))
            .Should().ThrowAsync<ArgumentNullException>();
        await FluentActions
            .Awaiting(() => AuthEngineEndpoints.HandleSessionAsync(new DefaultHttpContext(), null!, config))
            .Should().ThrowAsync<ArgumentNullException>();
        await FluentActions
            .Awaiting(() => AuthEngineEndpoints.HandleSessionAsync(new DefaultHttpContext(), guard, null!))
            .Should().ThrowAsync<ArgumentNullException>();
    }
}
