using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Policy;

/// <summary>
/// Requires the caller's home-landscape claim to match this deployment's landscape.
/// </summary>
/// <remarks>
/// An absent claim and a mismatched claim are reported as different problems on purpose.
/// Absent means onboarding has not written the claim yet, and the client's remedy is the
/// onboarding phase machine; mismatched means the user belongs to another landscape and
/// no amount of onboarding will change it.
/// </remarks>
public sealed class RequireHomeLandscape : IAuthorizationPolicy
{
    private readonly string _claimName;
    private readonly string _landscape;

    /// <summary>Creates the policy for a landscape, reading the claim named in configuration.</summary>
    public RequireHomeLandscape(AuthEngineConfig config, string landscape)
    {
        ArgumentNullException.ThrowIfNull(config);
        ArgumentException.ThrowIfNullOrWhiteSpace(landscape);

        this._claimName = config.HomeLandscapeClaim;
        this._landscape = landscape.Trim();
    }

    /// <inheritdoc />
    public Result<AuthClaims, IDomainProblem> Evaluate(AuthClaims claims)
    {
        ArgumentNullException.ThrowIfNull(claims);

        if (!claims.FindString(this._claimName).IsSome(out var home))
        {
            return Result.Err<AuthClaims, IDomainProblem>(AuthProblems.HomeLandscapeAbsent());
        }

        return string.Equals(home, this._landscape, StringComparison.Ordinal)
            ? Result.Ok<AuthClaims, IDomainProblem>(claims)
            : Result.Err<AuthClaims, IDomainProblem>(
                AuthProblems.HomeLandscapeMismatch(this._landscape));
    }
}
