using System.Net;
using System.Text;

namespace AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;

/// <summary>
/// A scripted <see cref="HttpMessageHandler" /> for driving the Logto-backed client
/// without a network.
/// </summary>
/// <remarks>
/// Shipped rather than kept in the test project because a consumer wiring the real
/// <c>LogtoCredentialClient</c> needs exactly this to test its own composition, and would
/// otherwise write it again.
/// </remarks>
public sealed class StubHttpMessageHandler : HttpMessageHandler
{
    private readonly Queue<Func<HttpRequestMessage, HttpResponseMessage>> _responses = new();
    private readonly List<HttpRequestMessage> _requests = [];

    private readonly List<string> _bodies = [];

    /// <summary>Gets every request the handler received, in order.</summary>
    public IReadOnlyList<HttpRequestMessage> Requests => this._requests;

    /// <summary>Gets the request bodies received, in order, so a test can assert on the form sent.</summary>
    public IReadOnlyList<string> CapturedBodies => this._bodies;

    /// <summary>
    /// Queues a raw response.
    /// </summary>
    /// <remarks>
    /// These queue methods return void rather than <c>this</c>. A fluent return that no
    /// caller chains is surface nobody uses, and the strict dead-code pass is right to
    /// say so; order is already expressed by call order.
    /// </remarks>
    public void Respond(Func<HttpRequestMessage, HttpResponseMessage> responder)
    {
        ArgumentNullException.ThrowIfNull(responder);
        this._responses.Enqueue(responder);
    }

    /// <summary>Queues a JSON response with the supplied status.</summary>
    public void RespondJson(HttpStatusCode status, string json) =>
        this.Respond(_ => new HttpResponseMessage(status)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        });

    /// <summary>Queues a bare status response with no body.</summary>
    public void RespondStatus(HttpStatusCode status) =>
        this.Respond(_ => new HttpResponseMessage(status));

    /// <summary>Queues a transport failure, as a dropped connection would produce.</summary>
    public void RespondTransportFailure() =>
        this.Respond(_ => throw new HttpRequestException("stubbed transport failure"));

    /// <summary>Queues a timeout, which surfaces as a cancelled task rather than a status.</summary>
    public void RespondTimeout() =>
        this.Respond(_ => throw new TaskCanceledException("stubbed timeout"));

    /// <inheritdoc />
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        this._requests.Add(request);
        this._bodies.Add(
            request.Content is null
                ? string.Empty
                : await request.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false));

        // An exhausted queue is a test-authoring error, not a server condition. Failing
        // loudly here beats returning a default response that would let an unexpected
        // extra call pass unnoticed.
        if (this._responses.Count == 0)
        {
            throw new InvalidOperationException(
                $"No stubbed response remains for {request.Method} {request.RequestUri}.");
        }

        return this._responses.Dequeue()(request);
    }
}
