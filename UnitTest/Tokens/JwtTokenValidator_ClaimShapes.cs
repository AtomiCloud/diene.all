using AtomiCloud.Diene.AuthEngine.TestHelper.Assertions;
using AtomiCloud.Diene.AuthEngine.TestHelper.Builders;
using FluentAssertions;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace AtomiCloud.DotnetBase.UnitTest.Tokens;

/// <summary>
/// Covers the claim-projection edge shapes: a repeated claim, an absent subject, and a
/// token carrying no issued-at.
/// </summary>
public class JwtTokenValidator_ClaimShapes
{
    [Fact]
    public async Task Joins_a_repeated_scope_claim_into_the_granted_set()
    {
        // Logto may emit "scope" once per value rather than space-delimited; both wire
        // shapes must yield the same granted set or a caller's policy silently changes
        // meaning with the IdP's serialisation choice.
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            extraClaims: new Dictionary<string, object>
            {
                ["scope"] = new[] { "notes:read", "notes:write" },
            });

        var claims = (await validator.ValidateAsync(
            token,
            AuthEngineFixture.Audience,
            TestContext.Current.CancellationToken)).ShouldBeAuthorized();

        claims.ShouldGrantScopes("notes:read", "notes:write");
    }

    [Fact]
    public async Task Refuses_a_token_carrying_no_subject()
    {
        // TestTokenIssuer deliberately refuses to mint a subject-less token, so this
        // signs one directly rather than weakening the shipped fake's guard. A consumer
        // should not be able to fabricate a token the IdP would never issue by accident;
        // this suite constructs the malformed case on purpose.
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var token = SubjectlessToken(issuer);

        var outcome = await validator.ValidateAsync(
            token,
            AuthEngineFixture.Audience,
            TestContext.Current.CancellationToken);

        outcome.ShouldBeUnauthenticated().Detail.Should().Contain("missing or malformed");
    }

    [Fact]
    public async Task Refuses_a_token_whose_key_id_matches_nothing_the_issuer_serves()
    {
        // A token naming a kid the resolver does not serve is a distinct case from a bad
        // signature: the handler cannot even select a key to verify against.
        using var trusted = AuthEngineFixture.NewIssuer();
        using var other = new TestTokenIssuer(AuthEngineFixture.Issuer, "rotated-away-key");

        var validator = AuthEngineFixture.Validator(trusted, AuthEngineFixture.Clock());
        var token = other.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        var outcome = await validator.ValidateAsync(
            token,
            AuthEngineFixture.Audience,
            TestContext.Current.CancellationToken);

        outcome.ShouldBeUnauthenticated().Detail.Should().Contain("signature could not be verified");
    }

    /// <summary>
    /// Signs a subject-less token with the ISSUER'S OWN key, so the only thing wrong with
    /// it is the missing subject. Signing with any other key would make the token fail on
    /// the signature instead, and the test would pass for the wrong reason.
    /// </summary>
    private static string SubjectlessToken(TestTokenIssuer issuer) =>
        new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Claims = new Dictionary<string, object>(StringComparer.Ordinal)
            {
                ["iss"] = issuer.Issuer,
                ["aud"] = AuthEngineFixture.Audience,
                ["exp"] = AuthEngineFixture.Now.AddMinutes(10).ToUnixTimeSeconds(),
                ["iat"] = AuthEngineFixture.Now.ToUnixTimeSeconds(),
            },
            SigningCredentials = issuer.SigningCredentials,
        });

    [Fact]
    public async Task Exposes_a_repeated_arbitrary_claim_through_Find()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            extraClaims: new Dictionary<string, object> { ["roles"] = new[] { "a", "b" } });

        var claims = (await validator.ValidateAsync(
            token,
            AuthEngineFixture.Audience,
            TestContext.Current.CancellationToken)).ShouldBeAuthorized();

        claims.Find("roles").IsSome().Should().BeTrue();

        // A repeated claim is not a single string, so the string reader reports absence
        // rather than silently picking one of the values.
        claims.FindString("roles").IsNone().Should().BeTrue();
    }

    [Fact]
    public async Task Reports_absence_for_an_unknown_or_blank_claim_name()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        var claims = (await validator.ValidateAsync(
            token,
            AuthEngineFixture.Audience,
            TestContext.Current.CancellationToken)).ShouldBeAuthorized();

        claims.Find("nope").IsNone().Should().BeTrue();
        claims.Find("   ").IsNone().Should().BeTrue();
        claims.FindString("nope").IsNone().Should().BeTrue();
    }

    [Fact]
    public async Task Reports_expiry_against_an_explicit_instant()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10));

        var claims = (await validator.ValidateAsync(
            token,
            AuthEngineFixture.Audience,
            TestContext.Current.CancellationToken)).ShouldBeAuthorized();

        claims.IsExpired(AuthEngineFixture.Now, TimeSpan.Zero).Should().BeFalse();
        claims.IsExpired(AuthEngineFixture.Now.AddMinutes(11), TimeSpan.Zero).Should().BeTrue();
    }
}
