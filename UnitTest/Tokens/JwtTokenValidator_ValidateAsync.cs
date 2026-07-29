using AtomiCloud.Diene.AuthEngine.TestHelper.Assertions;
using AtomiCloud.Diene.AuthEngine.TestHelper.Builders;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Tokens;

public class JwtTokenValidator_ValidateAsync
{
    [Fact]
    public async Task Accepts_a_correctly_signed_current_token()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var clock = AuthEngineFixture.Clock();
        var validator = AuthEngineFixture.Validator(issuer, clock);

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            ["notes:read", "notes:write"]);

        var outcome = await validator.ValidateAsync(token, AuthEngineFixture.Audience, TestContext.Current.CancellationToken);

        outcome.ShouldBeAuthorized()
            .ShouldHaveSubject(AuthEngineFixture.Subject)
            .ShouldGrantScopes("notes:read", "notes:write");
    }

    [Fact]
    public async Task Reports_issuer_and_expiry_on_the_validated_claims()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var clock = AuthEngineFixture.Clock();
        var validator = AuthEngineFixture.Validator(issuer, clock);

        var expiry = AuthEngineFixture.Now.AddMinutes(10);
        var token = issuer.Mint(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            expiry);

        var claims = (await validator.ValidateAsync(token, AuthEngineFixture.Audience, TestContext.Current.CancellationToken)).ShouldBeAuthorized();

        claims.Issuer.Should().Be(AuthEngineFixture.Issuer);
        claims.ExpiresAt.Should().Be(expiry);
        claims.IssuedAt.Should().Be(AuthEngineFixture.Now);
        claims.Audiences.Should().ContainSingle().Which.Should().Be(AuthEngineFixture.Audience);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("    ")]
    public async Task Refuses_a_blank_token(string? token)
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var outcome = await validator.ValidateAsync(token!, AuthEngineFixture.Audience, TestContext.Current.CancellationToken);

        outcome.ShouldBeUnauthenticated().Detail.Should().Contain("missing or malformed");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("   ")]
    public async Task Refuses_a_blank_audience(string? audience)
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());
        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        var outcome = await validator.ValidateAsync(token, audience!, TestContext.Current.CancellationToken);

        outcome.ShouldBeUnauthenticated().Detail.Should().Contain("not issued for this resource");
    }

    [Fact]
    public async Task Refuses_a_token_that_is_not_a_jwt()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var outcome = await validator.ValidateAsync("not.a.jwt", AuthEngineFixture.Audience, TestContext.Current.CancellationToken);

        outcome.ShouldBeUnauthenticated();
    }

    [Fact]
    public async Task Refuses_a_token_signed_by_another_key()
    {
        // The decisive security case: a well-formed token carrying every correct claim,
        // signed by a key the validator does not trust, must not validate.
        using var trusted = AuthEngineFixture.NewIssuer();
        using var attacker = new TestTokenIssuer(AuthEngineFixture.Issuer);

        var validator = AuthEngineFixture.Validator(trusted, AuthEngineFixture.Clock());
        var forged = attacker.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        var outcome = await validator.ValidateAsync(forged, AuthEngineFixture.Audience, TestContext.Current.CancellationToken);

        outcome.ShouldBeUnauthenticated();
    }

    [Fact]
    public async Task Refuses_a_token_from_an_untrusted_issuer()
    {
        using var other = new TestTokenIssuer("https://evil.test.invalid/oidc");
        var clock = AuthEngineFixture.Clock();

        // Trust the attacker's KEY but not its issuer, so only the issuer check can refuse.
        var validator = new JwtTokenValidator(
            AuthEngineFixture.Config(),
            other.KeyResolver,
            clock);

        var token = other.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        var outcome = await validator.ValidateAsync(token, AuthEngineFixture.Audience, TestContext.Current.CancellationToken);

        outcome.ShouldBeUnauthenticated().Detail.Should().Contain("untrusted issuer");
    }

    [Fact]
    public async Task Refuses_a_token_issued_for_another_audience()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            "https://other.test.invalid",
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        var outcome = await validator.ValidateAsync(token, AuthEngineFixture.Audience, TestContext.Current.CancellationToken);

        outcome.ShouldBeUnauthenticated().Detail.Should().Contain("not issued for this resource");
    }

    [Fact]
    public async Task Refuses_an_expired_token_using_the_injected_clock()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var clock = AuthEngineFixture.Clock();
        var validator = AuthEngineFixture.Validator(issuer, clock);

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        // Past the 10-minute lifetime AND past the 30-second skew.
        clock.Advance(TimeSpan.FromMinutes(11));

        var outcome = await validator.ValidateAsync(token, AuthEngineFixture.Audience, TestContext.Current.CancellationToken);

        outcome.ShouldBeUnauthenticated().Detail.Should().Contain("expired");
    }

    [Fact]
    public async Task Accepts_a_token_still_inside_the_expiry_skew()
    {
        // Just past expiry but within the configured 30-second skew: still accepted, which
        // is the behaviour the skew exists to provide.
        using var issuer = AuthEngineFixture.NewIssuer();
        var clock = AuthEngineFixture.Clock();
        var validator = AuthEngineFixture.Validator(issuer, clock);

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        clock.Advance(TimeSpan.FromMinutes(10) + TimeSpan.FromSeconds(10));

        var outcome = await validator.ValidateAsync(token, AuthEngineFixture.Audience, TestContext.Current.CancellationToken);

        outcome.ShouldBeAuthorized().ShouldHaveSubject(AuthEngineFixture.Subject);
    }

    [Fact]
    public async Task Refuses_a_token_whose_not_before_is_in_the_future()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var clock = AuthEngineFixture.Clock();
        var validator = AuthEngineFixture.Validator(issuer, clock);

        var token = issuer.Mint(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            AuthEngineFixture.Now.AddHours(2),
            notBefore: AuthEngineFixture.Now.AddHours(1));

        var outcome = await validator.ValidateAsync(token, AuthEngineFixture.Audience, TestContext.Current.CancellationToken);

        // Distinct from "expired": the remedy is to wait, not to re-authenticate.
        outcome.ShouldBeUnauthenticated().Detail.Should().Contain("not valid yet");
    }

    [Fact]
    public async Task Propagates_a_key_resolution_failure_unchanged()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var resolver = new FakeSigningKeyResolver(issuer.PublicKey)
        {
            Failure = AuthProblems.IdentityProviderUnreachable(),
        };

        var validator = new JwtTokenValidator(
            AuthEngineFixture.Config(),
            resolver,
            AuthEngineFixture.Clock());

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        var outcome = await validator.ValidateAsync(token, AuthEngineFixture.Audience, TestContext.Current.CancellationToken);

        outcome.ShouldBeUnauthenticated().Detail.Should().Contain("could not be reached");
        resolver.ResolveCount.Should().Be(1);
    }

    [Fact]
    public async Task Exposes_arbitrary_claims_through_the_claims_view()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            extraClaims: new Dictionary<string, object> { ["home_landscape"] = "lapras" });

        var claims = (await validator.ValidateAsync(token, AuthEngineFixture.Audience, TestContext.Current.CancellationToken)).ShouldBeAuthorized();

        claims.FindString("home_landscape").Get().Should().Be("lapras");
    }

    [Fact]
    public async Task Yields_no_scopes_when_the_scope_claim_is_absent()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        var claims = (await validator.ValidateAsync(token, AuthEngineFixture.Audience, TestContext.Current.CancellationToken)).ShouldBeAuthorized();

        claims.Scopes.Should().BeEmpty();
    }

    [Fact]
    public void Rejects_null_construction_arguments()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config();
        var clock = AuthEngineFixture.Clock();

        FluentActions.Invoking(() => new JwtTokenValidator(null!, issuer.KeyResolver, clock))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new JwtTokenValidator(config, null!, clock))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new JwtTokenValidator(config, issuer.KeyResolver, null!))
            .Should().Throw<ArgumentNullException>();
    }
}
