using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Client;

/// <summary>
/// Caches acquired access tokens per resource and renews them before expiry, so a caller
/// asks for a token rather than tracking lifetimes itself. This is the "silent refresh"
/// half of the alcohol token lifecycle.
/// </summary>
public sealed class TokenCache
{
    private readonly ICredentialClient _client;
    private readonly IAuthClock _clock;
    private readonly TokenLifetimeConfig _lifetimes;
    private readonly Dictionary<string, TokenResponse> _entries = new(StringComparer.Ordinal);
    private readonly SemaphoreSlim _gate = new(1, 1);

    /// <summary>Creates a cache over a credential client, clock, and lifetime settings.</summary>
    public TokenCache(ICredentialClient client, IAuthClock clock, TokenLifetimeConfig lifetimes)
    {
        ArgumentNullException.ThrowIfNull(client);
        ArgumentNullException.ThrowIfNull(clock);
        ArgumentNullException.ThrowIfNull(lifetimes);

        this._client = client;
        this._clock = clock;
        this._lifetimes = lifetimes;
    }

    /// <summary>
    /// Returns a usable token for the resource, acquiring one only when the cache has
    /// none or the cached one is within skew of expiring.
    /// </summary>
    /// <remarks>
    /// Acquisition happens under a gate so a burst of concurrent callers performs one
    /// token request rather than one each. The cache is re-checked after the gate is
    /// taken, because another caller may have populated it while this one waited.
    /// </remarks>
    public async Task<Result<TokenResponse, IDomainProblem>> GetAsync(
        string resource,
        IReadOnlyList<string>? scopes = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(resource))
        {
            return Result.Err<TokenResponse, IDomainProblem>(AuthProblems.AudienceMismatch());
        }

        if (this.TryReadFresh(resource, out var cached))
        {
            return Result.Ok<TokenResponse, IDomainProblem>(cached);
        }

        await this._gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (this.TryReadFresh(resource, out var raced))
            {
                return Result.Ok<TokenResponse, IDomainProblem>(raced);
            }

            var acquired = await this._client
                .AcquireAsync(resource, scopes ?? [], cancellationToken)
                .ConfigureAwait(false);

            if (acquired.IsFailure(out var failure))
            {
                return Result.Err<TokenResponse, IDomainProblem>(failure);
            }

            var token = acquired.Get();
            this._entries[resource] = token;
            return Result.Ok<TokenResponse, IDomainProblem>(token);
        }
        finally
        {
            this._gate.Release();
        }
    }

    /// <summary>
    /// Drops every cached token. Called on sign-out and after session revocation, so a
    /// revoked session cannot keep serving from cache until its tokens age out.
    /// </summary>
    public void Clear()
    {
        this._gate.Wait();
        try
        {
            this._entries.Clear();
        }
        finally
        {
            this._gate.Release();
        }
    }

    private bool TryReadFresh(string resource, out TokenResponse token)
    {
        if (this._entries.TryGetValue(resource, out var candidate) &&
            !candidate.NeedsRefresh(this._clock.UtcNow, this._lifetimes.ExpirySkew))
        {
            token = candidate;
            return true;
        }

        token = null!;
        return false;
    }
}
