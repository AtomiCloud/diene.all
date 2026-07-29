using System.Security.Cryptography;
using System.Text;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine;

/// <summary>
/// Mints digest-backed app-handoff nonces and exchanges them exactly once for
/// Logto one-time sign-in tokens.
/// </summary>
public sealed class DeferredTokenMinter : IDeferredTokenMinter
{
    internal const int NonceByteLength = 32;
    internal const int NonceEncodedLength = 43;
    internal const int OneTimeTokenExpiresIn = 120;
    internal static readonly TimeSpan NonceLifetime = TimeSpan.FromMinutes(15);

    private readonly IDeferredTokenStore _store;
    private readonly IAuthManagement _management;
    private readonly IAuthClock _clock;

    /// <summary>Creates a minter over the consumer's persistent store and Logto management seam.</summary>
    public DeferredTokenMinter(
        IDeferredTokenStore store,
        IAuthManagement management,
        IAuthClock clock)
    {
        ArgumentNullException.ThrowIfNull(store);
        ArgumentNullException.ThrowIfNull(management);
        ArgumentNullException.ThrowIfNull(clock);

        this._store = store;
        this._management = management;
        this._clock = clock;
    }

    /// <inheritdoc />
    public async Task<Result<DeferredHandoff, IDomainProblem>> Mint(
        DeferredPayload payload,
        CancellationToken cancellationToken = default)
    {
        if (payload is null ||
            string.IsNullOrWhiteSpace(payload.Subject) ||
            string.IsNullOrWhiteSpace(payload.Email))
        {
            return Result.Err<DeferredHandoff, IDomainProblem>(AuthProblems.MalformedToken());
        }

        var nonce = EncodeNonce(RandomNumberGenerator.GetBytes(NonceByteLength));
        var normalized = new DeferredPayload(payload.Subject.Trim(), payload.Email.Trim());
        var stored = await this._store
            .Put(Digest(nonce), normalized, NonceLifetime, cancellationToken)
            .ConfigureAwait(false);

        if (stored.IsFailure(out var failure))
        {
            return Result.Err<DeferredHandoff, IDomainProblem>(failure);
        }

        return Result.Ok<DeferredHandoff, IDomainProblem>(
            new DeferredHandoff(nonce, this._clock.UtcNow + NonceLifetime));
    }

    /// <inheritdoc />
    public async Task<Result<DeferredExchange, IDomainProblem>> Exchange(
        string token,
        CancellationToken cancellationToken = default)
    {
        if (!IsNonce(token)) return Expired<DeferredExchange>();

        var digest = Digest(token);
        var claimed = await this._store.Consume(digest, cancellationToken).ConfigureAwait(false);
        if (claimed.IsFailure(out _) || !claimed.Get().IsSome(out var payload))
        {
            return Expired<DeferredExchange>();
        }

        var user = await this._management.GetUser(payload.Subject, cancellationToken).ConfigureAwait(false);
        if (user.IsFailure(out _) || !user.Get().IsSome(out var account) ||
            account.IsSuspended || account.PrimaryEmail is null ||
            !AsciiEqualsIgnoreCase(account.PrimaryEmail, payload.Email))
        {
            return await this.RevokeAndExpire(digest, cancellationToken).ConfigureAwait(false);
        }

        var minted = await this._management
            .MintOneTimeToken(account.PrimaryEmail, cancellationToken)
            .ConfigureAwait(false);
        if (minted.IsFailure(out _) || string.IsNullOrWhiteSpace(minted.Get()))
        {
            return await this.RevokeAndExpire(digest, cancellationToken).ConfigureAwait(false);
        }

        var settled = await this._store
            .Settle(digest, DeferredTokenState.Consumed, cancellationToken)
            .ConfigureAwait(false);
        if (settled.IsFailure(out _))
        {
            return await this.RevokeAndExpire(digest, cancellationToken).ConfigureAwait(false);
        }

        return Result.Ok<DeferredExchange, IDomainProblem>(
            new DeferredExchange(minted.Get(), account.PrimaryEmail, OneTimeTokenExpiresIn));
    }

    /// <summary>Returns the lowercase SHA-256 digest used as the persistent store key.</summary>
    public static string Digest(string token)
    {
        ArgumentNullException.ThrowIfNull(token);
        return Convert.ToHexString(SHA256.HashData(Encoding.ASCII.GetBytes(token))).ToLowerInvariant();
    }

    private static string EncodeNonce(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static bool IsNonce(string? token) =>
        token is { Length: NonceEncodedLength } && token.All(IsBase64UrlCharacter);

    private static bool IsBase64UrlCharacter(char value) =>
        value is >= 'A' and <= 'Z' or >= 'a' and <= 'z' or >= '0' and <= '9' or '-' or '_';

    private static bool AsciiEqualsIgnoreCase(string left, string right)
    {
        if (left.Length != right.Length) return false;

        for (var index = 0; index < left.Length; index++)
        {
            if (AsciiLower(left[index]) != AsciiLower(right[index])) return false;
        }

        return true;
    }

    private static char AsciiLower(char value) => value is >= 'A' and <= 'Z' ? (char)(value + 32) : value;

    private async Task<Result<DeferredExchange, IDomainProblem>> RevokeAndExpire(
        string digest,
        CancellationToken cancellationToken)
    {
        _ = await this._store
            .Settle(digest, DeferredTokenState.Revoked, cancellationToken)
            .ConfigureAwait(false);
        return Expired<DeferredExchange>();
    }

    private static Result<T, IDomainProblem> Expired<T>() =>
        Result.Err<T, IDomainProblem>(new AppHandoffExpired());
}
