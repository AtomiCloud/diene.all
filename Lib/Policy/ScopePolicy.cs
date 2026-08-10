using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Policy;

/// <summary>Requires that the caller holds every listed scope.</summary>
public sealed class RequireAllScopes : IAuthorizationPolicy
{
    private readonly IReadOnlyList<string> _required;

    /// <summary>Creates the policy over the scopes a caller must hold.</summary>
    public RequireAllScopes(params string[] required)
    {
        ArgumentNullException.ThrowIfNull(required);
        this._required = [.. required.Where(scope => !string.IsNullOrWhiteSpace(scope))];
    }

    /// <inheritdoc />
    public Result<AuthClaims, IDomainProblem> Evaluate(AuthClaims claims)
    {
        ArgumentNullException.ThrowIfNull(claims);

        var missing = Scopes.Missing(claims.Scopes, this._required);
        return missing.Count == 0
            ? Result.Ok<AuthClaims, IDomainProblem>(claims)
            : Result.Err<AuthClaims, IDomainProblem>(
                AuthProblems.MissingScopes(claims.Scopes, missing));
    }
}

/// <summary>Requires that the caller holds at least one of the listed scopes.</summary>
public sealed class RequireAnyScope : IAuthorizationPolicy
{
    private readonly IReadOnlyList<string> _accepted;

    /// <summary>Creates the policy over the scopes any one of which suffices.</summary>
    public RequireAnyScope(params string[] accepted)
    {
        ArgumentNullException.ThrowIfNull(accepted);
        this._accepted = [.. accepted.Where(scope => !string.IsNullOrWhiteSpace(scope))];
    }

    /// <inheritdoc />
    public Result<AuthClaims, IDomainProblem> Evaluate(AuthClaims claims)
    {
        ArgumentNullException.ThrowIfNull(claims);

        // An empty accepted set refuses rather than admits. "Any of nothing" is not
        // satisfiable, and treating it as a pass would turn a misconfigured policy into
        // an open door — the failure direction that costs the most.
        if (this._accepted.Count == 0)
        {
            return Result.Err<AuthClaims, IDomainProblem>(
                AuthProblems.MissingScopes(claims.Scopes, this._accepted));
        }

        var granted = new HashSet<string>(claims.Scopes, StringComparer.Ordinal);
        return this._accepted.Any(granted.Contains)
            ? Result.Ok<AuthClaims, IDomainProblem>(claims)
            : Result.Err<AuthClaims, IDomainProblem>(
                AuthProblems.MissingScopes(claims.Scopes, this._accepted));
    }
}
