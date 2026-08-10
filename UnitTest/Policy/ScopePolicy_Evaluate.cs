using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.TestHelper.Assertions;
using AtomiCloud.Diene.AuthEngine.Tokens;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Policy;

public class ScopePolicy_Evaluate
{
    private static async Task<AuthClaims> ClaimsWith(params string[] scopes)
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());
        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            scopes);

        var outcome = await validator.ValidateAsync(
            token,
            AuthEngineFixture.Audience,
            TestContext.Current.CancellationToken);

        return outcome.ShouldBeAuthorized();
    }

    [Fact]
    public async Task RequireAllScopes_admits_a_caller_holding_every_scope()
    {
        var claims = await ClaimsWith("notes:read", "notes:write", "extra");

        new RequireAllScopes("notes:read", "notes:write").Evaluate(claims)
            .ShouldBeAuthorized().ShouldHaveSubject(AuthEngineFixture.Subject);
    }

    [Fact]
    public async Task RequireAllScopes_admits_when_nothing_is_required()
    {
        var claims = await ClaimsWith();

        new RequireAllScopes().Evaluate(claims).ShouldBeAuthorized();
    }

    [Fact]
    public async Task RequireAllScopes_reports_only_the_missing_scopes()
    {
        var claims = await ClaimsWith("notes:read");

        var refusal = new RequireAllScopes("notes:read", "notes:write", "notes:delete")
            .Evaluate(claims)
            .ShouldRequireScopes("notes:write", "notes:delete");

        refusal.Granted.Should().BeEquivalentTo(["notes:read"]);
    }

    [Fact]
    public async Task RequireAllScopes_ignores_blank_entries_in_its_requirement_list()
    {
        var claims = await ClaimsWith("notes:read");

        new RequireAllScopes("notes:read", "", "   ").Evaluate(claims).ShouldBeAuthorized();
    }

    [Fact]
    public async Task RequireAnyScope_admits_a_caller_holding_one_accepted_scope()
    {
        var claims = await ClaimsWith("notes:read");

        new RequireAnyScope("notes:write", "notes:read").Evaluate(claims).ShouldBeAuthorized();
    }

    [Fact]
    public async Task RequireAnyScope_refuses_a_caller_holding_none_of_them()
    {
        var claims = await ClaimsWith("other:scope");

        new RequireAnyScope("notes:read", "notes:write")
            .Evaluate(claims)
            .ShouldRequireScopes("notes:read", "notes:write");
    }

    [Fact]
    public async Task RequireAnyScope_refuses_when_its_accepted_set_is_empty()
    {
        // "Any of nothing" is unsatisfiable. Admitting here would turn a misconfigured
        // policy into an open door, so the empty set fails closed.
        var claims = await ClaimsWith("notes:read");

        new RequireAnyScope().Evaluate(claims).ShouldBeUnauthorized();
    }

    [Fact]
    public async Task RequireAnyScope_treats_an_all_blank_list_as_empty_and_refuses()
    {
        var claims = await ClaimsWith("notes:read");

        new RequireAnyScope("", "  ").Evaluate(claims).ShouldBeUnauthorized();
    }

    [Fact]
    public void Policies_reject_a_null_requirement_array()
    {
        FluentActions.Invoking(() => new RequireAllScopes(null!)).Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new RequireAnyScope(null!)).Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Policies_reject_null_claims()
    {
        FluentActions.Invoking(() => new RequireAllScopes("a").Evaluate(null!))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new RequireAnyScope("a").Evaluate(null!))
            .Should().Throw<ArgumentNullException>();
    }
}
