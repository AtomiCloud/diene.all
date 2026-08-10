using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;

namespace AtomiCloud.Diene.AuthEngine.Tokens;

/// <summary>
/// Builders for the problem-typed failures this library returns. Every failure is one of
/// the two published catalog problems — <see cref="Unauthenticated" /> when the caller's
/// identity could not be established, <see cref="Unauthorized" /> when an established
/// identity lacks a permission. The distinction is load-bearing: it is the difference
/// between "log in" and "you may not do this", and consumers route them differently.
/// </summary>
public static class AuthProblems
{
    /// <summary>The token was absent, malformed, or otherwise unparseable.</summary>
    public static IDomainProblem MalformedToken() =>
        new Unauthenticated("The bearer token is missing or malformed.");

    /// <summary>The token's signature did not verify against the issuer's keys.</summary>
    public static IDomainProblem InvalidSignature() =>
        new Unauthenticated("The token signature could not be verified.");

    /// <summary>The token has passed its expiry instant.</summary>
    public static IDomainProblem ExpiredToken() => new Unauthenticated("The token has expired.");

    /// <summary>
    /// The token is not valid yet — its <c>nbf</c> is in the future. Distinct from an
    /// expired token: the remedy is to wait, not to re-authenticate, and conflating the
    /// two sends a caller into a pointless refresh loop.
    /// </summary>
    public static IDomainProblem TokenNotYetValid() => new Unauthenticated("The token is not valid yet.");

    /// <summary>The token's issuer did not match the issuer baked in at build time.</summary>
    public static IDomainProblem IssuerMismatch() =>
        new Unauthenticated("The token was issued by an untrusted issuer.");

    /// <summary>The token's audience did not include the expected resource.</summary>
    public static IDomainProblem AudienceMismatch() =>
        new Unauthenticated("The token was not issued for this resource.");

    /// <summary>An authenticated caller lacked one or more required scopes.</summary>
    public static IDomainProblem MissingScopes(
        IReadOnlyList<string> granted,
        IReadOnlyList<string> required) =>
        new Unauthorized(
            "The authenticated caller lacks a required scope.",
            granted ?? [],
            required ?? []);

    /// <summary>An authenticated caller's home-landscape claim did not match the expected landscape.</summary>
    public static IDomainProblem HomeLandscapeMismatch(string expected) =>
        new Unauthorized(
            $"The caller's home landscape does not permit access to '{expected}'.",
            [],
            [expected]);

    /// <summary>The caller has no home-landscape claim, so onboarding has not completed.</summary>
    public static IDomainProblem HomeLandscapeAbsent() =>
        new Unauthorized(
            "The caller has no home landscape claim; onboarding has not completed.",
            [],
            []);

    /// <summary>
    /// The identity provider could not be reached. Reported as an authentication failure
    /// because the caller's identity could not be established — a caller that cannot
    /// reach the IdP must fail closed, never proceed as though unauthenticated access
    /// were permitted.
    /// </summary>
    public static IDomainProblem IdentityProviderUnreachable() =>
        new Unauthenticated("The identity provider could not be reached.");

    /// <summary>The configured client id or secret was rejected by the identity provider.</summary>
    public static IDomainProblem InvalidClientCredentials() =>
        new Unauthenticated("The configured client credentials were rejected.");

    /// <summary>
    /// The identity provider refused the request with an unmapped status. The status is
    /// carried in the detail so a diagnosis does not require re-running the call.
    /// </summary>
    public static IDomainProblem IdentityProviderRejected(string status) =>
        new Unauthenticated($"The identity provider rejected the request with status {status}.");
}
