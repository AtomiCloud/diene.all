using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using Microsoft.IdentityModel.Tokens;

namespace AtomiCloud.Diene.AuthEngine.Tokens;

/// <summary>
/// The key-material boundary. Isolating retrieval behind this seam is what lets a
/// consumer test validation without reaching an IdP over the network, and it is the
/// port the shipped TestHelper fakes.
/// </summary>
public interface ISigningKeyResolver
{
    /// <summary>Returns the issuer's current signing keys.</summary>
    Task<Result<IReadOnlyList<SecurityKey>, IDomainProblem>> ResolveAsync(
        CancellationToken cancellationToken = default);
}
