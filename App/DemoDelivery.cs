using System.Globalization;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.CoreUtils;
using AtomiCloud.Diene.ServerEngine.Webhooks;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// Builds signed deliveries the way mercury would, so the demo can drive its own receiver.
/// </summary>
/// <remarks>
/// The signing side is written out here on purpose. A demo that only ever verified would prove
/// the receiver accepts what this same code produced, which is a tautology; producing the bytes
/// from the contract's own description — ASCII timestamp, <c>0x2e</c>, exact body — is what
/// makes a green result mean the wire format is right.
/// </remarks>
public static class DemoDelivery
{
    /// <summary>The demo's per-platform internal webhook secret.</summary>
    public const string Secret = "demo-internal-webhook-secret";

    /// <summary>Composes a C0 §11 version-1 envelope as compact UTF-8 JSON.</summary>
    public static byte[] Envelope(string provider, string eventId, DateTimeOffset receivedAt, int attempt)
    {
        var instant = Wire.Format(receivedAt);
        var envelope = new JsonObject
        {
            ["version"] = WebhookProtocol.EnvelopeVersion,
            ["eventId"] = eventId,
            ["dedupId"] = $"native:{eventId}",
            ["tenantId"] = "tenant-1",
            ["routeId"] = "route-1",
            ["provider"] = provider,
            ["landingLandscape"] = "lapras",
            ["receivedAt"] = instant,
            ["providerEventId"] = $"prov-{eventId}",
            ["providerTimestamp"] = instant,
            ["providerSequence"] = "7",
            ["providerHeaders"] = new JsonObject { ["x-demo"] = new JsonArray("one", "two") },
            ["payload"] = new JsonObject
            {
                ["contentType"] = "application/json",
                ["bodyBase64"] = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{{\"note\":\"{eventId}\"}}")),
            },
            ["delivery"] = new JsonObject
            {
                ["endpointId"] = "endpoint-1",
                ["attempt"] = attempt,
                ["replay"] = false,
            },
        };

        return Encoding.UTF8.GetBytes(envelope.ToJsonString());
    }

    /// <summary>Renders the <c>X-Atomi-Webhook-Signature</c> value for a body at an instant.</summary>
    public static string Signature(DateTimeOffset signedAt, ReadOnlySpan<byte> body, string secret)
    {
        var seconds = signedAt.ToUnixTimeSeconds();
        var stamp = Encoding.ASCII.GetBytes(seconds.ToString(CultureInfo.InvariantCulture));
        var signed = new byte[stamp.Length + 1 + body.Length];
        stamp.CopyTo(signed.AsSpan());
        signed[stamp.Length] = WebhookProtocol.SignedPayloadSeparator;
        body.CopyTo(signed.AsSpan(stamp.Length + 1));

        var digest = HMACSHA256.HashData(Encoding.UTF8.GetBytes(secret), signed);
        return string.Create(
            CultureInfo.InvariantCulture,
            $"t={seconds}, v1={Convert.ToHexString(digest).ToLowerInvariant()}");
    }

    /// <summary>Builds a delivery request, optionally with a deliberately wrong signature.</summary>
    public static HttpRequestMessage Request(
        string provider,
        byte[] body,
        DateTimeOffset signedAt,
        string secret = Secret,
        string mediaType = WebhookProtocol.MediaType)
    {
        ArgumentNullException.ThrowIfNull(body);

        var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"/{WebhookProtocol.RoutePrefix}/{provider}")
        {
            Content = new ByteArrayContent(body),
        };
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(mediaType);
        request.Headers.TryAddWithoutValidation(
            WebhookProtocol.SignatureHeader,
            Signature(signedAt, body, secret));
        return request;
    }
}
