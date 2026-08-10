using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>What a handler decided about one delivery.</summary>
public enum WebhookOutcome
{
    /// <summary>
    /// The handler owns this event and has finished with it. Renders as exactly 200, which
    /// completes mercury's obligation for this endpoint.
    /// </summary>
    Processed = 0,

    /// <summary>
    /// This event is not this receiver's. Renders as 421 so mercury recompiles the address
    /// and retries the same endpoint, instead of treating it as a real failure.
    /// </summary>
    NotMine = 1,
}

/// <summary>
/// A per-provider receiver for internal webhook deliveries.
/// </summary>
/// <remarks>
/// <para>
/// A handler MUST be idempotent: mercury durably accepts and acks the provider before an
/// endpoint obligation finishes, so retries and cross-landscape provider retries can both
/// deliver the same event twice. Use <see cref="WebhookIdempotency.KeyOf" /> as the domain
/// key; delivery attempt and arrival order are not usable for the purpose.
/// </para>
/// <para>
/// The signature is already verified and the envelope already validated before a handler is
/// called, which is why this seam takes a typed envelope and not raw bytes. A handler that
/// received raw bytes would each have to re-implement verification, and C0 explicitly forbids
/// hand-rolling it per handler.
/// </para>
/// </remarks>
public interface IWebhookHandler
{
    /// <summary>Gets the lowercase provider id this handler serves.</summary>
    string Provider { get; }

    /// <summary>
    /// Handles one delivery. Returning a typed problem means a REAL error — mercury will
    /// retry with backoff — so a handler must not use it to mean "not mine".
    /// </summary>
    Task<Result<WebhookOutcome, IDomainProblem>> HandleAsync(
        WebhookEnvelope envelope,
        CancellationToken cancellationToken = default);
}
