using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using StackExchange.Redis;

namespace AtomiCloud.DotnetBase.App.Webhooks;

/// <summary>
/// Receives mercury deliveries for the <c>note</c> provider. The route, the signature check,
/// envelope parsing, and the status mapping all ship in the server engine; this is the thin
/// business half.
/// </summary>
/// <remarks>
/// The replies mercury reads are not this handler's to choose freely: <c>Processed</c> answers
/// exactly 200, <c>NotMine</c> answers 421, and a typed problem is a REAL error that mercury
/// will retry. Answering 404 for an unowned event would make mercury retry for its full
/// 72-hour window and then dead-letter it, which is the reason <c>NotMine</c> exists.
/// </remarks>
/// <param name="cache">The ephemeral cache holding the dedup ledger and the effect log.</param>
public sealed class NoteWebhookHandler(IConnectionMultiplexer cache) : IWebhookHandler
{
    /// <summary>The provider this handler owns.</summary>
    public const string ProviderName = "note";

    /// <summary>Key under which every processed delivery records its one side effect.</summary>
    public const string EffectKey = "webhook:note:processed";

    private const string DedupPrefix = "webhook:note:seen:";

    /// <summary>
    /// How long a delivery stays deduplicated. Comfortably beyond mercury's retry window, so a
    /// late redelivery still finds the claim.
    /// </summary>
    public static readonly TimeSpan DedupWindow = TimeSpan.FromDays(4);

    /// <inheritdoc />
    public string Provider => ProviderName;

    /// <inheritdoc />
    public async Task<Result<WebhookOutcome, IDomainProblem>> HandleAsync(
        WebhookEnvelope envelope,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(envelope);
        cancellationToken.ThrowIfCancellationRequested();

        if (!string.Equals(envelope.Provider, ProviderName, StringComparison.Ordinal))
            return Result.Ok<WebhookOutcome, IDomainProblem>(WebhookOutcome.NotMine);

        var database = cache.GetDatabase();

        // Dedup on the engine's idempotency key, never on delivery.attempt or arrival order:
        // mercury acks the provider before this obligation finishes, so a redelivery and a
        // cross-landscape provider retry can both arrive.
        var claimed = await database
            .StringSetAsync(DedupPrefix + WebhookIdempotency.KeyOf(envelope), envelope.EventId, DedupWindow, When.NotExists)
            .ConfigureAwait(false);

        // The side effect happens exactly once. A replay finds the claim already taken, skips
        // it, and still answers 200 — that is what idempotent means to mercury.
        if (claimed) await database.SetAddAsync(EffectKey, envelope.EventId).ConfigureAwait(false);

        return Result.Ok<WebhookOutcome, IDomainProblem>(WebhookOutcome.Processed);
    }
}
