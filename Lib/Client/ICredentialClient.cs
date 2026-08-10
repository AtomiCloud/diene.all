using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Client;

/// <summary>
/// Client-side credential acquisition. This is the network boundary consumers must fake
/// to test their own code, and it is the port the shipped TestHelper provides a fake for.
/// </summary>
public interface ICredentialClient
{
    /// <summary>Acquires an access token for a resource via the client-credentials flow.</summary>
    Task<Result<TokenResponse, IDomainProblem>> AcquireAsync(
        string resource,
        IReadOnlyList<string> scopes,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Exchanges a refresh token for a new token pair. With rotation enabled the response
    /// carries a NEW refresh token and the presented one is retired, so replaying it is
    /// what lets the IdP detect theft.
    /// </summary>
    Task<Result<RefreshedTokens, IDomainProblem>> RefreshAsync(
        string refreshToken,
        string resource,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Revokes every session for a user through the Logto Management API.
    /// </summary>
    Task<Result<Unit, IDomainProblem>> RevokeUserSessionsAsync(
        string userId,
        CancellationToken cancellationToken = default);
}
