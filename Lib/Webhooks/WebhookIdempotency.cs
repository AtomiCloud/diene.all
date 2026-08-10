using System.Globalization;

namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>Builds the domain idempotency key a handler must dedup on.</summary>
public static class WebhookIdempotency
{
    /// <summary>
    /// Composes the <c>(tenantId, routeId, dedupId)</c> key C0 §11 names as the domain
    /// idempotency key.
    /// </summary>
    /// <remarks>
    /// Each component is length-prefixed rather than simply joined by a separator. Tenant and
    /// route ids are opaque, so a separator could legitimately appear inside one, and a plain
    /// join would then let two different triples produce the same key — collapsing two
    /// tenants' events into one dedup entry, which is the exact failure a dedup key exists to
    /// prevent.
    /// </remarks>
    public static string KeyOf(WebhookEnvelope envelope)
    {
        ArgumentNullException.ThrowIfNull(envelope);

        return string.Create(
            CultureInfo.InvariantCulture,
            $"{envelope.TenantId.Length}:{envelope.TenantId}|{envelope.RouteId.Length}:{envelope.RouteId}|{envelope.DedupId.Length}:{envelope.DedupId}");
    }
}
