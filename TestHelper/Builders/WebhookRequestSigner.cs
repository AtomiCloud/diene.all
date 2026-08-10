using System.Globalization;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using AtomiCloud.Diene.ServerEngine.Webhooks;

namespace AtomiCloud.Diene.ServerEngine.TestHelper.Builders;

/// <summary>
/// Signs delivery requests the way mercury does, so a consumer can drive its own receiver.
/// </summary>
/// <remarks>
/// The signing side is implemented from the contract's own words — ASCII timestamp, the
/// <c>0x2e</c> separator, then the exact body bytes — rather than by calling the library's
/// verifier backwards. A signer built out of the verifier would agree with it by construction,
/// including when both are wrong, and a consumer's green test would prove nothing about the wire
/// format mercury actually sends.
/// </remarks>
public static class WebhookRequestSigner
{
    /// <summary>The key used when a test does not care which secret is in play.</summary>
    public const string DefaultKey = "test-internal-webhook-secret";

    /// <summary>Renders the <c>X-Atomi-Webhook-Signature</c> value for a body at an instant.</summary>
    public static string Header(DateTimeOffset signedAt, ReadOnlySpan<byte> body, string key = DefaultKey)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);

        var seconds = signedAt.ToUnixTimeSeconds();
        return string.Create(
            CultureInfo.InvariantCulture,
            $"t={seconds}, v1={Digest(seconds, body, key)}");
    }

    /// <summary>Computes the lowercase-hex <c>v1</c> digest for a body at a timestamp.</summary>
    public static string Digest(long seconds, ReadOnlySpan<byte> body, string key = DefaultKey)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);

        var stamp = Encoding.ASCII.GetBytes(seconds.ToString(CultureInfo.InvariantCulture));
        var signed = new byte[stamp.Length + 1 + body.Length];
        stamp.CopyTo(signed.AsSpan());
        signed[stamp.Length] = WebhookProtocol.SignedPayloadSeparator;
        body.CopyTo(signed.AsSpan(stamp.Length + 1));

        return Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(key), signed)).ToLowerInvariant();
    }

    /// <summary>
    /// Builds a signed delivery request. Every part a test might need to break — the secret, the
    /// signing instant, the media type, the header value itself — is overridable.
    /// </summary>
    public static HttpRequestMessage Request(
        string provider,
        byte[] body,
        DateTimeOffset signedAt,
        string key = DefaultKey,
        string mediaType = WebhookProtocol.MediaType,
        string? header = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(provider);
        ArgumentNullException.ThrowIfNull(body);

        var request = new HttpRequestMessage(HttpMethod.Post, $"/{WebhookProtocol.RoutePrefix}/{provider}")
        {
            Content = new ByteArrayContent(body),
        };
        // Parse rather than construct, so a test can supply a media type WITH parameters —
        // "…+json; charset=utf-8" is a legal delivery header and the constructor rejects it.
        request.Content.Headers.ContentType = MediaTypeHeaderValue.Parse(mediaType);

        // TryAddWithoutValidation is required: a test that supplies a deliberately malformed
        // header must reach the receiver's parser, and the client's own validation would reject
        // it first — the check under test would never run.
        request.Headers.TryAddWithoutValidation(
            WebhookProtocol.SignatureHeader,
            header ?? Header(signedAt, body, key));

        return request;
    }
}
