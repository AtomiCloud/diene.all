using System.Collections.Concurrent;
using System.Globalization;
using System.Text;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.ServerEngine.Webhooks;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// The demo's webhook receiver for one provider, showing the shape a real handler takes.
/// </summary>
/// <remarks>
/// It keeps a seen-key set because C0 requires handlers to be idempotent, and the key is built
/// with the shipped helper rather than by hand. A handler that deduped on
/// <c>delivery.attempt</c> would treat a cross-landscape provider retry as a new event, which
/// is the duplicate-work bug the contract's idempotency clause exists to prevent.
/// </remarks>
public sealed class DemoWebhookHandler : IWebhookHandler
{
    /// <summary>The provider this demo handler claims.</summary>
    public const string DemoProvider = "stripe";

    /// <summary>The event id the demo disowns, to show the 421 reply.</summary>
    public const string DisownedEventId = "evt-not-mine";

    private readonly ConcurrentDictionary<string, int> _seen = new(StringComparer.Ordinal);

    /// <inheritdoc />
    public string Provider => DemoProvider;

    /// <summary>Gets how many times each idempotency key has been delivered.</summary>
    public IReadOnlyDictionary<string, int> Seen => this._seen;

    /// <summary>Gets a human-readable line for the most recent delivery.</summary>
    public string LastDescription { get; private set; } = "none";

    /// <inheritdoc />
    public Task<Result<WebhookOutcome, IDomainProblem>> HandleAsync(
        WebhookEnvelope envelope,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(envelope);
        cancellationToken.ThrowIfCancellationRequested();

        var key = WebhookIdempotency.KeyOf(envelope);
        var deliveries = this._seen.AddOrUpdate(key, 1, (_, count) => count + 1);
        this.LastDescription = Describe(envelope, deliveries);

        return Task.FromResult(
            Result.Ok<WebhookOutcome, IDomainProblem>(
                string.Equals(envelope.EventId, DisownedEventId, StringComparison.Ordinal)
                    ? WebhookOutcome.NotMine
                    : WebhookOutcome.Processed));
    }

    /// <summary>Renders every envelope field a handler is entitled to rely on.</summary>
    public static string Describe(WebhookEnvelope envelope, int deliveries)
    {
        ArgumentNullException.ThrowIfNull(envelope);

        var headers = string.Join(
            ';',
            envelope.ProviderHeaders.Select(header => $"{header.Key}={string.Join('|', header.Value)}"));

        return string.Create(
            CultureInfo.InvariantCulture,
            $"v{envelope.Version} {envelope.Provider}/{envelope.EventId} tenant={envelope.TenantId} " +
            $"route={envelope.RouteId} dedup={envelope.DedupId} landing={envelope.LandingLandscape} " +
            $"received={envelope.ReceivedAt:O} providerEvent={envelope.ProviderEventId ?? "-"} " +
            $"providerTime={envelope.ProviderTimestamp?.ToString("O", CultureInfo.InvariantCulture) ?? "-"} " +
            $"providerSeq={envelope.ProviderSequence ?? "-"} headers=[{headers}] " +
            $"payload={envelope.Payload.ContentType}:{Encoding.UTF8.GetString(envelope.Payload.Body.Span)} " +
            $"endpoint={envelope.Delivery.EndpointId} attempt={envelope.Delivery.Attempt} " +
            $"replay={envelope.Delivery.Replay} deliveries={deliveries}");
    }
}
