using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using Microsoft.IdentityModel.Tokens;

namespace AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;

/// <summary>
/// Serves a fixed key set, so validation runs without reaching a discovery endpoint.
/// </summary>
public sealed class FakeSigningKeyResolver : ISigningKeyResolver
{
    private readonly IReadOnlyList<SecurityKey> _keys;

    /// <summary>Creates a resolver over the supplied keys.</summary>
    public FakeSigningKeyResolver(params SecurityKey[] keys)
    {
        ArgumentNullException.ThrowIfNull(keys);
        this._keys = [.. keys];
    }

    /// <summary>Gets or sets a failure returned instead of the keys.</summary>
    public IDomainProblem? Failure { get; set; }

    /// <summary>Gets how many times keys were resolved.</summary>
    public int ResolveCount { get; private set; }

    /// <inheritdoc />
    public Task<Result<IReadOnlyList<SecurityKey>, IDomainProblem>> ResolveAsync(
        CancellationToken cancellationToken = default)
    {
        this.ResolveCount++;

        return Task.FromResult(
            this.Failure is not null
                ? Result.Err<IReadOnlyList<SecurityKey>, IDomainProblem>(this.Failure)
                : Result.Ok<IReadOnlyList<SecurityKey>, IDomainProblem>(this._keys));
    }
}
