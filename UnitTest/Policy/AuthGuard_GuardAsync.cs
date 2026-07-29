using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.TestHelper.Assertions;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Policy;

public class AuthGuard_GuardAsync
{
    [Fact]
    public async Task Admits_a_valid_token_satisfying_every_policy()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock(), config));

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            ["notes:read"],
            new Dictionary<string, object> { ["home_landscape"] = "lapras" });

        var outcome = await guard.GuardAsync(
            token,
            AuthEngineFixture.Audience,
            [new RequireAllScopes("notes:read"), new RequireHomeLandscape(config, "lapras")],
            TestContext.Current.CancellationToken);

        outcome.ShouldBeAuthorized().ShouldHaveSubject(AuthEngineFixture.Subject);
    }

    [Fact]
    public async Task Reports_a_validation_failure_without_consulting_policies()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var clock = AuthEngineFixture.Clock();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, clock));

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        clock.Advance(TimeSpan.FromHours(1));

        var outcome = await guard.GuardAsync(
            token,
            AuthEngineFixture.Audience,
            [new RequireAllScopes("notes:read")],
            TestContext.Current.CancellationToken);

        // Unauthenticated, not Unauthorized: the token never established an identity, so
        // the scope requirement was never the reason it failed.
        outcome.ShouldBeUnauthenticated().Detail.Should().Contain("expired");
    }

    [Fact]
    public async Task Stops_at_the_first_policy_that_refuses()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock(), config));

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        // Both policies would refuse; the reported problem must be the FIRST one, so the
        // message points at the first thing actually wrong rather than an arbitrary one.
        var outcome = await guard.GuardAsync(
            token,
            AuthEngineFixture.Audience,
            [new RequireAllScopes("notes:read"), new RequireHomeLandscape(config, "lapras")],
            TestContext.Current.CancellationToken);

        outcome.ShouldRequireScopes("notes:read");
    }

    [Fact]
    public async Task Admits_when_no_policies_are_supplied()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock()));

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        var outcome = await guard.GuardAsync(
            token,
            AuthEngineFixture.Audience,
            [],
            TestContext.Current.CancellationToken);

        outcome.ShouldBeAuthorized();
    }

    [Fact]
    public async Task GuardOrAnyAsync_admits_a_caller_holding_one_of_the_scopes()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock()));

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            ["notes:read"]);

        var outcome = await guard.GuardOrAnyAsync(
            token,
            AuthEngineFixture.Audience,
            ["notes:write", "notes:read"],
            TestContext.Current.CancellationToken);

        outcome.ShouldBeAuthorized();
    }

    [Fact]
    public async Task GuardOrAnyAsync_refuses_a_caller_holding_none_of_them()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock()));

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            ["other"]);

        var outcome = await guard.GuardOrAnyAsync(
            token,
            AuthEngineFixture.Audience,
            ["notes:read"],
            TestContext.Current.CancellationToken);

        outcome.ShouldRequireScopes("notes:read");
    }

    [Fact]
    public void Rejects_a_null_validator() =>
        FluentActions.Invoking(() => new AuthGuard(null!)).Should().Throw<ArgumentNullException>();

    [Fact]
    public async Task Rejects_a_null_policy_sequence()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock()));

        await FluentActions
            .Awaiting(() => guard.GuardAsync("t", "a", null!, TestContext.Current.CancellationToken))
            .Should().ThrowAsync<ArgumentNullException>();
    }
}
