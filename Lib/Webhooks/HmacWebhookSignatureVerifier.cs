using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.ServerEngine.Config;

namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>
/// The C0 §11 verifier: <c>HMAC-SHA256(ASCII(t) || 0x2e || body, key)</c>, compared in
/// constant time against every live rotation key, inside a bounded timestamp window.
/// </summary>
/// <remarks>
/// The clock arrives through the published auth-engine clock seam rather than a second one of
/// this package's own. A service that pins the clock for token expiry and forgets to pin it
/// for webhook freshness has two different "now"s, and the resulting flake looks like clock
/// skew from mercury.
/// </remarks>
public sealed class HmacWebhookSignatureVerifier(
    IWebhookSecretProvider secrets,
    IAuthClock clock,
    WebhookConfig config) : IWebhookSignatureVerifier
{
    private readonly IWebhookSecretProvider _secrets = secrets ?? throw new ArgumentNullException(nameof(secrets));
    private readonly IAuthClock _clock = clock ?? throw new ArgumentNullException(nameof(clock));
    private readonly WebhookConfig _config = config ?? throw new ArgumentNullException(nameof(config));

    /// <inheritdoc />
    public Result<Unit, WebhookSignatureFailure> Verify(string? header, ReadOnlySpan<byte> body)
    {
        var parsed = WebhookSignatureHeader.Parse(header);
        if (parsed.IsFailure(out var malformed)) return Refuse(malformed);

        var signature = parsed.Get();
        var now = this._clock.UtcNow.ToUnixTimeSeconds();
        if (Math.Abs(now - signature.Timestamp) > (long)this._config.Tolerance.TotalSeconds)
        {
            return Refuse(WebhookSignatureFailure.StaleTimestamp);
        }

        var keys = this._secrets.SigningKeys;
        if (keys.Count == 0) return Refuse(WebhookSignatureFailure.NoSigningKeys);

        var signed = SignedPayload(signature.Timestamp, body);

        // Every key is tried and the results are OR-ed, rather than returning on the first
        // match. Short-circuiting would make the response time reveal WHICH rotation key
        // matched, and the comparison itself is constant-time for the same reason.
        var matched = false;
        foreach (var key in keys)
        {
            var computed = HMACSHA256.HashData(Encoding.UTF8.GetBytes(key), signed);
            matched |= CryptographicOperations.FixedTimeEquals(computed, signature.Digest);
        }

        return matched
            ? Result.Ok<Unit, WebhookSignatureFailure>(default)
            : Refuse(WebhookSignatureFailure.DigestMismatch);
    }

    private static byte[] SignedPayload(long timestamp, ReadOnlySpan<byte> body)
    {
        var stamp = Encoding.ASCII.GetBytes(timestamp.ToString(CultureInfo.InvariantCulture));
        var buffer = new byte[stamp.Length + 1 + body.Length];
        stamp.CopyTo(buffer.AsSpan());
        buffer[stamp.Length] = WebhookProtocol.SignedPayloadSeparator;
        body.CopyTo(buffer.AsSpan(stamp.Length + 1));
        return buffer;
    }

    private static Result<Unit, WebhookSignatureFailure> Refuse(WebhookSignatureFailure failure) =>
        Result.Err<Unit, WebhookSignatureFailure>(failure);
}
