using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.TestHelper.Assertions;
using AtomiCloud.Diene.AuthEngine.Tokens;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Policy;

public class HomeLandscapePolicy_Evaluate
{
    private static async Task<AuthClaims> ClaimsWith(string? homeLandscape)
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var extra = homeLandscape is null
            ? null
            : new Dictionary<string, object> { ["home_landscape"] = homeLandscape };

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            extraClaims: extra);

        var outcome = await validator.ValidateAsync(
            token,
            AuthEngineFixture.Audience,
            TestContext.Current.CancellationToken);

        return outcome.ShouldBeAuthorized();
    }

    [Fact]
    public async Task Admits_a_caller_whose_home_landscape_matches()
    {
        var claims = await ClaimsWith("lapras");

        new RequireHomeLandscape(AuthEngineFixture.Config(), "lapras").Evaluate(claims)
            .ShouldBeAuthorized();
    }

    [Fact]
    public async Task Refuses_a_caller_from_another_landscape()
    {
        var claims = await ClaimsWith("entei");

        var refusal = new RequireHomeLandscape(AuthEngineFixture.Config(), "lapras")
            .Evaluate(claims)
            .ShouldBeUnauthorized();

        refusal.Detail.Should().Contain("does not permit access to 'lapras'");
        refusal.Required.Should().BeEquivalentTo(["lapras"]);
    }

    [Fact]
    public async Task Reports_an_absent_claim_differently_from_a_mismatch()
    {
        // Absent means onboarding has not written the claim and the remedy is the phase
        // machine; mismatched means the user belongs elsewhere and never will match.
        // Collapsing the two would send a legitimately-onboarding user to a dead end.
        var claims = await ClaimsWith(null);

        var refusal = new RequireHomeLandscape(AuthEngineFixture.Config(), "lapras")
            .Evaluate(claims)
            .ShouldBeUnauthorized();

        refusal.Detail.Should().Contain("onboarding has not completed");
        refusal.Required.Should().BeEmpty();
    }

    [Fact]
    public async Task Treats_a_blank_claim_value_as_absent()
    {
        var claims = await ClaimsWith("   ");

        new RequireHomeLandscape(AuthEngineFixture.Config(), "lapras")
            .Evaluate(claims)
            .ShouldBeUnauthorized()
            .Detail.Should().Contain("onboarding has not completed");
    }

    [Fact]
    public async Task Reads_the_claim_name_from_configuration()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config("landscape_home");
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock(), config);

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            extraClaims: new Dictionary<string, object> { ["landscape_home"] = "lapras" });

        var claims = (await validator.ValidateAsync(
            token,
            AuthEngineFixture.Audience,
            TestContext.Current.CancellationToken)).ShouldBeAuthorized();

        new RequireHomeLandscape(config, "lapras").Evaluate(claims).ShouldBeAuthorized();
    }

    [Fact]
    public void Rejects_invalid_construction()
    {
        var config = AuthEngineFixture.Config();

        FluentActions.Invoking(() => new RequireHomeLandscape(null!, "lapras"))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new RequireHomeLandscape(config, "  "))
            .Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Rejects_null_claims() =>
        FluentActions.Invoking(() => new RequireHomeLandscape(AuthEngineFixture.Config(), "lapras").Evaluate(null!))
            .Should().Throw<ArgumentNullException>();
}
