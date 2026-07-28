using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.ServerEngine.Mvc;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Microsoft.Net.Http.Headers;

namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>
/// The C0 §11 delivery endpoint: <c>POST /internal/webhooks/{provider}</c>.
/// </summary>
/// <remarks>
/// This ships as a concrete controller, not a base class a service subclasses. The tri-state
/// reply contract and the mandatory signature check are the same for every provider, and every
/// receiver that re-implemented them would be one place the 401-versus-421 distinction could
/// be got wrong. A service supplies only an <see cref="IWebhookHandler" />.
/// </remarks>
[Route(WebhookProtocol.RoutePrefix)]
public sealed class WebhookController(
    IWebhookSignatureVerifier verifier,
    WebhookHandlerRegistry registry,
    ILogger<WebhookController> logger) : AtomiController
{
    private readonly IWebhookSignatureVerifier _verifier =
        verifier ?? throw new ArgumentNullException(nameof(verifier));

    private readonly WebhookHandlerRegistry _registry = registry ?? throw new ArgumentNullException(nameof(registry));

    private readonly ILogger<WebhookController> _logger = logger ?? throw new ArgumentNullException(nameof(logger));

    /// <summary>Receives one delivery for a provider.</summary>
    [HttpPost("{provider}")]
    public async Task<IActionResult> ReceiveAsync(string provider, CancellationToken cancellationToken)
    {
        var body = await ReadBodyAsync(this.Request, cancellationToken).ConfigureAwait(false);

        // Order is load-bearing. The signature is checked over the raw bytes FIRST — before
        // the media type, before parsing — so an unauthenticated caller learns nothing about
        // what this receiver would have accepted, and no parser runs on unverified input.
        var signature = this._verifier.Verify(this.Request.Headers[WebhookProtocol.SignatureHeader], body.Span);
        if (signature.IsFailure(out var refusal))
        {
            this._logger.LogWarning(
                "Refused webhook delivery for {Provider}: {Refusal}",
                provider,
                refusal);

            return this.Protocol(
                StatusCodes.Status401Unauthorized,
                "Webhook Signature Rejected",
                $"The delivery signature was refused: {refusal}.");
        }

        if (!IsExpectedMediaType(this.Request.Headers[HeaderNames.ContentType]))
        {
            return this.Protocol(
                StatusCodes.Status415UnsupportedMediaType,
                "Unsupported Webhook Media Type",
                $"A delivery must be sent as '{WebhookProtocol.MediaType}'.");
        }

        var parsed = WebhookEnvelopeReader.Read(body.Span);
        if (parsed.IsFailure(out var malformed))
        {
            return this.Protocol(
                StatusCodes.Status400BadRequest,
                "Malformed Webhook Envelope",
                $"The delivery envelope is invalid — {malformed}");
        }

        var envelope = parsed.Get();

        // A body naming a different provider than the route means the compiled address was
        // wrong for this event. That is exactly what 421 is for; a 4xx would send mercury into
        // its 72h retry window against an endpoint that will never accept it.
        if (!string.Equals(envelope.Provider, provider, StringComparison.OrdinalIgnoreCase))
        {
            return this.NotMine(
                $"This endpoint serves '{provider}' but the delivery declares '{envelope.Provider}'.");
        }

        if (!this._registry.TryResolve(provider, out var handler))
        {
            return this.NotMine($"No handler is registered for provider '{provider}'.");
        }

        var outcome = await handler.HandleAsync(envelope, cancellationToken).ConfigureAwait(false);

        // A typed problem from a handler is a REAL error. It is raised so the shared
        // exception-to-Problem filter renders it exactly as any other domain failure, which
        // keeps mercury's retry decision driven by the consumer's own status policy.
        if (outcome.IsFailure(out var problem)) throw problem.ToException();

        if (outcome.Get() == WebhookOutcome.NotMine)
        {
            return this.NotMine($"The registered handler for '{provider}' does not own this event.");
        }

        this._logger.LogInformation(
            "Processed webhook delivery {EventId} attempt {Attempt} for {Provider}",
            envelope.EventId,
            envelope.Delivery.Attempt,
            provider);

        return this.StatusCode(WebhookProtocol.ProcessedStatus);
    }

    private static async Task<ReadOnlyMemory<byte>> ReadBodyAsync(
        HttpRequest request,
        CancellationToken cancellationToken)
    {
        using var buffer = new MemoryStream();
        await request.Body.CopyToAsync(buffer, cancellationToken).ConfigureAwait(false);
        return buffer.ToArray();
    }

    /// <summary>
    /// Compares only the media type, ignoring any parameters such as a charset, so a signer
    /// that appends one is not refused for a reason the contract does not state.
    /// </summary>
    private static bool IsExpectedMediaType(string? contentType) =>
        MediaTypeHeaderValue.TryParse(contentType, out var parsed) &&
        string.Equals(parsed.MediaType.Value, WebhookProtocol.MediaType, StringComparison.OrdinalIgnoreCase);

    private IActionResult NotMine(string detail) =>
        this.Protocol(WebhookProtocol.NotMineStatus, "Misdirected Webhook Delivery", detail);

    private IActionResult Protocol(int status, string title, string detail) =>
        ProblemEnvelope.ToResult(
            ProblemEnvelope.FromProtocol(
                status,
                title,
                detail,
                this.Request.Path.Value ?? "/",
                this.TraceId));
}
