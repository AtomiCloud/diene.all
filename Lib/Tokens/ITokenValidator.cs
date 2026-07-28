using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Tokens;

/// <summary>
/// Server-side token validation. Implementations return problem-typed failures rather
/// than throwing, so a caller composes validation into a Result pipeline.
/// </summary>
public interface ITokenValidator
{
    /// <summary>
    /// Validates a bearer token's signature, issuer, audience, and expiry, and returns
    /// its claims on success.
    /// </summary>
    /// <param name="token">The raw compact-serialization JWT.</param>
    /// <param name="audience">The resource indicator the token must be issued for.</param>
    /// <param name="cancellationToken">Cancels key-material retrieval.</param>
    Task<Result<AuthClaims, IDomainProblem>> ValidateAsync(
        string token,
        string audience,
        CancellationToken cancellationToken = default);
}
