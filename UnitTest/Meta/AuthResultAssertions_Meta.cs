using AtomiCloud.Diene.AuthEngine.TestHelper.Assertions;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Meta;

/// <summary>
/// Meta tier: assert-the-asserter. Every shipped assertion is proven to PASS on a
/// known-good case and to FAIL on a known-bad one.
/// </summary>
/// <remarks>
/// The failing half is the half that matters. An assertion that has only ever been seen
/// to pass is indistinguishable from one that cannot fail, and a consumer would then be
/// shipping green tests that assert nothing.
/// </remarks>
public class AuthResultAssertions_Meta
{
    private static async Task<Result<AuthClaims, IDomainProblem>> Authorized(params string[] scopes)
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());
        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            scopes);

        return await validator.ValidateAsync(
            token,
            AuthEngineFixture.Audience,
            TestContext.Current.CancellationToken);
    }

    private static Result<AuthClaims, IDomainProblem> Refused(IDomainProblem problem) =>
        Result.Err<AuthClaims, IDomainProblem>(problem);

    [Fact]
    public async Task ShouldBeAuthorized_passes_on_success_and_fails_on_a_refusal()
    {
        (await Authorized()).ShouldBeAuthorized().Subject.Should().Be(AuthEngineFixture.Subject);

        FluentActions.Invoking(() => Refused(AuthProblems.ExpiredToken()).ShouldBeAuthorized())
            .Should().Throw<AuthAssertionException>()
            .WithMessage("*unauthenticated*expired*");
    }

    [Fact]
    public async Task ShouldBeRefused_passes_on_a_refusal_and_fails_on_success()
    {
        Refused(AuthProblems.ExpiredToken()).ShouldBeRefused().Id.Should().Be("unauthenticated");

        var authorized = await Authorized();
        FluentActions.Invoking(() => authorized.ShouldBeRefused())
            .Should().Throw<AuthAssertionException>()
            .WithMessage($"*{AuthEngineFixture.Subject}*");
    }

    [Fact]
    public void ShouldBeUnauthenticated_passes_on_that_type_and_fails_on_the_other()
    {
        Refused(AuthProblems.ExpiredToken()).ShouldBeUnauthenticated().Should().NotBeNull();

        FluentActions.Invoking(() =>
                Refused(AuthProblems.MissingScopes([], ["a"])).ShouldBeUnauthenticated())
            .Should().Throw<AuthAssertionException>()
            .WithMessage("*Expected an Unauthenticated problem*Unauthorized*");
    }

    [Fact]
    public void ShouldBeUnauthorized_passes_on_that_type_and_fails_on_the_other()
    {
        Refused(AuthProblems.MissingScopes([], ["a"])).ShouldBeUnauthorized().Should().NotBeNull();

        FluentActions.Invoking(() => Refused(AuthProblems.ExpiredToken()).ShouldBeUnauthorized())
            .Should().Throw<AuthAssertionException>()
            .WithMessage("*Expected an Unauthorized problem*Unauthenticated*");
    }

    [Fact]
    public void ShouldRequireScopes_passes_on_a_match_regardless_of_order_and_fails_otherwise()
    {
        Refused(AuthProblems.MissingScopes([], ["b", "a"]))
            .ShouldRequireScopes("a", "b")
            .Should().NotBeNull();

        FluentActions.Invoking(() =>
                Refused(AuthProblems.MissingScopes([], ["a"])).ShouldRequireScopes("a", "b"))
            .Should().Throw<AuthAssertionException>()
            .WithMessage("*Expected required scopes [a, b]*found [a]*");
    }

    [Fact]
    public void ShouldRequireScopes_rejects_a_null_expectation() =>
        FluentActions.Invoking(() => Refused(AuthProblems.MissingScopes([], [])).ShouldRequireScopes(null!))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public async Task ShouldGrantScopes_passes_on_a_match_and_fails_on_a_mismatch()
    {
        var claims = (await Authorized("notes:read", "notes:write")).ShouldBeAuthorized();

        claims.ShouldGrantScopes("notes:write", "notes:read").Should().BeSameAs(claims);

        FluentActions.Invoking(() => claims.ShouldGrantScopes("notes:read"))
            .Should().Throw<AuthAssertionException>()
            .WithMessage("*Expected granted scopes [notes:read]*notes:read, notes:write*");
    }

    [Fact]
    public async Task ShouldGrantScopes_rejects_null_arguments()
    {
        var claims = (await Authorized()).ShouldBeAuthorized();

        FluentActions.Invoking(() => AuthResultAssertions.ShouldGrantScopes(null!, "a"))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => claims.ShouldGrantScopes(null!))
            .Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task ShouldHaveSubject_passes_on_a_match_and_fails_on_a_mismatch()
    {
        var claims = (await Authorized()).ShouldBeAuthorized();

        claims.ShouldHaveSubject(AuthEngineFixture.Subject).Should().BeSameAs(claims);

        FluentActions.Invoking(() => claims.ShouldHaveSubject("someone-else"))
            .Should().Throw<AuthAssertionException>()
            .WithMessage($"*Expected subject 'someone-else'*{AuthEngineFixture.Subject}*");
    }

    [Fact]
    public void ShouldHaveSubject_rejects_null_claims() =>
        FluentActions.Invoking(() => AuthResultAssertions.ShouldHaveSubject(null!, "x"))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void The_assertion_exception_exposes_its_standard_constructors()
    {
        new AuthAssertionException().Should().BeAssignableTo<Exception>();
        new AuthAssertionException("boom").Message.Should().Be("boom");

        var inner = new InvalidOperationException("cause");
        new AuthAssertionException("boom", inner).InnerException.Should().BeSameAs(inner);
    }
}
