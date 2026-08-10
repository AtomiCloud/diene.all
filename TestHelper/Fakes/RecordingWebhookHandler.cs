using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.ServerEngine.Webhooks;

namespace AtomiCloud.Diene.ServerEngine.TestHelper.Fakes;

/// <summary>
/// A webhook handler that records what it was handed and answers whatever the test set.
/// </summary>
/// <remarks>
/// It records the ENVELOPES rather than a count, because the assertions worth making about a
/// receiver are about content: that the payload survived base64 decoding intact, that a redelivery
/// arrived with the same idempotency key, that provider headers came through lowercase. A counting
/// fake can only tell you something arrived.
/// </remarks>
public sealed class RecordingWebhookHandler : IWebhookHandler
{
    private readonly List<WebhookEnvelope> _received = [];

    /// <summary>Creates a handler for a provider that answers <see cref="WebhookOutcome.Processed" />.</summary>
    public RecordingWebhookHandler(string provider = "stripe")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(provider);
        this.Provider = provider;
    }

    /// <inheritdoc />
    public string Provider { get; }

    /// <summary>Gets or sets the outcome returned when no failure is set.</summary>
    public WebhookOutcome Outcome { get; set; } = WebhookOutcome.Processed;

    /// <summary>Gets or sets a typed problem returned instead of an outcome.</summary>
    public IDomainProblem? Failure { get; set; }

    /// <summary>Gets every envelope handed to this handler, in arrival order.</summary>
    public IReadOnlyList<WebhookEnvelope> Received => this._received;

    /// <summary>Gets the idempotency keys of every delivery, in arrival order.</summary>
    public IReadOnlyList<string> Keys => [.. this._received.Select(WebhookIdempotency.KeyOf)];

    /// <inheritdoc />
    public Task<Result<WebhookOutcome, IDomainProblem>> HandleAsync(
        WebhookEnvelope envelope,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(envelope);
        cancellationToken.ThrowIfCancellationRequested();

        this._received.Add(envelope);

        return Task.FromResult(
            this.Failure is null
                ? Result.Ok<WebhookOutcome, IDomainProblem>(this.Outcome)
                : Result.Err<WebhookOutcome, IDomainProblem>(this.Failure));
    }
}
