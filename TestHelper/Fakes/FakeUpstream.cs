using System.Net;
using System.Text;

namespace AtomiCloud.Diene.ApiEngine.TestHelper.Fakes;

/// <summary>
/// One request the fake upstream received, kept so a test can assert on what was sent as well
/// as on what came back.
/// </summary>
/// <param name="Method">The request method.</param>
/// <param name="Uri">The absolute request URI, which shows the base address that was applied.</param>
/// <param name="Authorization">
/// The <c>Authorization</c> header value, or null when the request was unauthenticated. This is
/// what proves a per-backend token reached the backend it belongs to and no other.
/// </param>
/// <param name="Body">The request body, or the empty string when there was none.</param>
public sealed record RecordedRequest(HttpMethod Method, Uri? Uri, string? Authorization, string Body);

/// <summary>
/// A scripted upstream: an <see cref="HttpMessageHandler" /> a consumer plugs in as the primary
/// handler of a registered backend, so the whole engine pipeline runs with no network.
/// </summary>
/// <remarks>
/// Deliberately a message handler rather than a fake typed client. Faking the client would skip
/// the auth handler, the retry, and the capture — the parts most worth testing — and would let a
/// suite pass while the pipeline it depends on is misassembled.
/// </remarks>
public sealed class FakeUpstream : HttpMessageHandler
{
    private readonly Queue<Func<HttpRequestMessage, HttpResponseMessage>> _responses = new();
    private readonly List<RecordedRequest> _requests = [];

    /// <summary>Creates a fake upstream, named for diagnostics.</summary>
    public FakeUpstream(string name)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        Name = name;
    }

    /// <summary>Gets the name this fake reports in its diagnostics.</summary>
    public string Name { get; }

    /// <summary>Gets every request received, in order.</summary>
    public IReadOnlyList<RecordedRequest> Requests => _requests;

    /// <summary>Gets how many requests reached this upstream.</summary>
    /// <remarks>
    /// The count is the retry assertion: a profile that retries exactly once shows two attempts
    /// here, and one that retries twice — or not at all — is visible without reading a log.
    /// </remarks>
    public int Attempts => _requests.Count;

    /// <summary>Queues a raw response.</summary>
    /// <remarks>
    /// Returns void rather than <c>this</c>: a fluent return no caller chains is surface nobody
    /// uses, and queue order is already expressed by call order.
    /// </remarks>
    public void Respond(Func<HttpRequestMessage, HttpResponseMessage> responder)
    {
        ArgumentNullException.ThrowIfNull(responder);
        _responses.Enqueue(responder);
    }

    /// <summary>Queues a successful JSON payload.</summary>
    public void RespondOk(string json) => RespondJson(HttpStatusCode.OK, json);

    /// <summary>Queues a JSON response with the supplied status and media type.</summary>
    public void RespondJson(HttpStatusCode status, string json, string mediaType = "application/json") =>
        Respond(_ => new HttpResponseMessage(status)
        {
            Content = new StringContent(json, Encoding.UTF8, mediaType),
        });

    /// <summary>Queues an RFC 9457 problem response under the problem media type.</summary>
    public void RespondProblem(HttpStatusCode status, string json) =>
        RespondJson(status, json, "application/problem+json");

    /// <summary>Queues a non-JSON failure body, such as a gateway's HTML error page.</summary>
    public void RespondText(HttpStatusCode status, string body, string mediaType = "text/html") =>
        Respond(_ => new HttpResponseMessage(status)
        {
            Content = new StringContent(body, Encoding.UTF8, mediaType),
        });

    /// <summary>Queues a bare status response carrying no body at all.</summary>
    public void RespondStatus(HttpStatusCode status) => Respond(_ => new HttpResponseMessage(status));

    /// <summary>
    /// Queues an opaque network-level failure, as a refused connection or a DNS blip produces.
    /// </summary>
    /// <remarks>
    /// No status is attached, which is exactly what makes it opaque and therefore the one
    /// condition the engine retries.
    /// </remarks>
    public void RespondNetworkFailure() =>
        Respond(_ => throw new HttpRequestException($"fake network failure at upstream '{Name}'"));

    /// <summary>Queues a client timeout.</summary>
    /// <remarks>
    /// Shaped as a cancelled task wrapping a <see cref="TimeoutException" />, which is how a real
    /// <c>HttpClient</c> timeout surfaces. A fake that threw a plain cancellation would let code
    /// pass here and misreport timeouts in production.
    /// </remarks>
    public void RespondTimeout() =>
        Respond(_ => throw new TaskCanceledException(
            $"fake timeout at upstream '{Name}'",
            new TimeoutException()));

    /// <inheritdoc />
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        _requests.Add(new RecordedRequest(
            request.Method,
            request.RequestUri,
            request.Headers.Authorization?.ToString(),
            request.Content is null
                ? string.Empty
                : await request.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false)));

        // An exhausted queue is a test-authoring error, not a server condition. Failing loudly
        // beats a default response that would let an unexpected extra call pass unnoticed — and
        // an unexpected extra call is precisely the retry defect this fake exists to catch.
        if (_responses.Count == 0)
        {
            throw new InvalidOperationException(
                $"Upstream '{Name}' has no stubbed response left for {request.Method} {request.RequestUri}.");
        }

        return _responses.Dequeue()(request);
    }
}
