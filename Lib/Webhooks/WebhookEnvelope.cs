namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>The provider payload carried by a delivery, already base64-decoded.</summary>
/// <param name="ContentType">The provider's own content type, or <c>application/octet-stream</c>.</param>
/// <param name="Body">The exact provider body bytes.</param>
public sealed record WebhookPayload(string ContentType, ReadOnlyMemory<byte> Body);

/// <summary>Which obligation this request is, and which attempt.</summary>
/// <param name="EndpointId">The snapshotted registration this delivery belongs to.</param>
/// <param name="Attempt">The attempt number, starting at 1 and increasing monotonically.</param>
/// <param name="Replay">Whether this is a console-triggered replay.</param>
public sealed record WebhookDelivery(string EndpointId, int Attempt, bool Replay);

/// <summary>
/// The C0 §11 delivery envelope, version 1.
/// </summary>
/// <remarks>
/// Field order is not semantic and unknown fields are ignored while <c>version == 1</c>, so
/// this type is a projection of the fields a receiver is entitled to rely on — not a mirror
/// of whatever mercury happens to send.
/// </remarks>
/// <param name="Version">The envelope version; always 1 for this contract.</param>
/// <param name="EventId">The opaque landing-landscape event id.</param>
/// <param name="DedupId">The intake dedup id, <c>native:</c> or <c>sha256:</c> prefixed.</param>
/// <param name="TenantId">The stable opaque tenant id.</param>
/// <param name="RouteId">The stable opaque route id.</param>
/// <param name="Provider">The lowercase provider id.</param>
/// <param name="LandingLandscape">The landscape the event landed in.</param>
/// <param name="ReceivedAt">When mercury durably accepted the provider event.</param>
/// <param name="ProviderEventId">The provider's own event id, when it has one.</param>
/// <param name="ProviderTimestamp">The provider's own timestamp, when it has one.</param>
/// <param name="ProviderSequence">The provider's own ordering token, when it has one.</param>
/// <param name="ProviderHeaders">The adapter-owned business header allowlist, lowercase names.</param>
/// <param name="Payload">The provider payload.</param>
/// <param name="Delivery">This obligation's delivery metadata.</param>
public sealed record WebhookEnvelope(
    int Version,
    string EventId,
    string DedupId,
    string TenantId,
    string RouteId,
    string Provider,
    string LandingLandscape,
    DateTimeOffset ReceivedAt,
    string? ProviderEventId,
    DateTimeOffset? ProviderTimestamp,
    string? ProviderSequence,
    IReadOnlyDictionary<string, IReadOnlyList<string>> ProviderHeaders,
    WebhookPayload Payload,
    WebhookDelivery Delivery);
