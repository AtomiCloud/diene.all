using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Policy;

/// <summary>
/// A check applied to already-validated claims. Policies compose: each returns the claims
/// unchanged on success so they chain through <see cref="Result{T,E}.Then{TOut}(Func{T,Result{TOut,E}})" />.
/// </summary>
public interface IAuthorizationPolicy
{
    /// <summary>Evaluates the policy, returning the claims on success or a typed problem on refusal.</summary>
    Result<AuthClaims, IDomainProblem> Evaluate(AuthClaims claims);
}
