namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>
/// The parts of the C0 §11 webhook wire contract that are fixed for every receiver.
/// </summary>
/// <remarks>
/// These are constants rather than configuration on purpose. The route, header name, media
/// type, and envelope version are what mercury and every receiver agree on; a service that
/// could configure them could silently stop receiving deliveries while still looking healthy.
/// </remarks>
public static class WebhookProtocol
{
    /// <summary>The route prefix the receiver is mounted at.</summary>
    public const string RoutePrefix = "internal/webhooks";

    /// <summary>The header carrying the delivery timestamp and HMAC digest.</summary>
    public const string SignatureHeader = "X-Atomi-Webhook-Signature";

    /// <summary>The exact request media type a delivery carries.</summary>
    public const string MediaType = "application/vnd.atomi.webhook.v1+json";

    /// <summary>The only envelope version this receiver accepts.</summary>
    public const int EnvelopeVersion = 1;

    /// <summary>The separator byte between the ASCII timestamp and the body in the signed payload.</summary>
    public const byte SignedPayloadSeparator = 0x2e;

    /// <summary>The status that completes a delivery obligation.</summary>
    public const int ProcessedStatus = 200;

    /// <summary>
    /// The only signal for "this event is not mine". C0 forbids 404 for ownership, because
    /// mercury reads 404 as a real endpoint failure and would retry for the full 72h window.
    /// </summary>
    public const int NotMineStatus = 421;
}
