using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Policy;

/// <summary>
/// Composes token validation with a policy chain — the server-side entry point a
/// consumer calls per request.
/// </summary>
public sealed class AuthGuard
{
    private readonly ITokenValidator _validator;

    /// <summary>Creates a guard over a token validator.</summary>
    public AuthGuard(ITokenValidator validator)
    {
        ArgumentNullException.ThrowIfNull(validator);
        this._validator = validator;
    }

    /// <summary>
    /// Validates the bearer token then applies every policy in order, stopping at the
    /// first refusal so the reported problem is the first thing that actually failed.
    /// </summary>
    public async Task<Result<AuthClaims, IDomainProblem>> GuardAsync(
        string token,
        string audience,
        IEnumerable<IAuthorizationPolicy> policies,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(policies);

        var validated = await this._validator
            .ValidateAsync(token, audience, cancellationToken)
            .ConfigureAwait(false);

        if (validated.IsFailure(out var failure)) return Result.Err<AuthClaims, IDomainProblem>(failure);

        var claims = validated.Get();
        foreach (var policy in policies)
        {
            var outcome = policy.Evaluate(claims);
            if (outcome.IsFailure(out var refusal)) return Result.Err<AuthClaims, IDomainProblem>(refusal);
        }

        return Result.Ok<AuthClaims, IDomainProblem>(claims);
    }

    /// <summary>
    /// Validates and requires any one of the supplied scopes. Mirrors the zinc seed's
    /// <c>GuardOrAnyAsync</c>, which dotnet-api's SIT exercises end to end.
    /// </summary>
    public Task<Result<AuthClaims, IDomainProblem>> GuardOrAnyAsync(
        string token,
        string audience,
        string[] scopes,
        CancellationToken cancellationToken = default) =>
        this.GuardAsync(token, audience, [new RequireAnyScope(scopes)], cancellationToken);
}
