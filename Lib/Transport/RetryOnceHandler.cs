namespace AtomiCloud.Diene.ApiEngine.Transport;

/// <summary>
/// The whole client-side resilience profile: on an OPAQUE network-level failure, retry
/// exactly once over a fresh connection, then surface the failure.
/// </summary>
/// <remarks>
/// This is not load balancing, and the omissions are the design. There is no physical URL
/// list, no round-robin, no circuit breaker, and no failover ladder: the gray-zone DNS A-set
/// is the platform's only failover mechanism, and a client-side copy of a routing decision is
/// a second, staler source of truth for something the client cannot see.
/// <para>
/// A received HTTP status is never retried — not even a 5xx. A status means the request
/// arrived and was processed, so retrying it risks repeating a non-idempotent effect for no
/// gain. What this covers is the narrow window a runtime reports as one opaque error with no
/// per-origin detail, which is exactly where a single fresh-connection attempt helps.
/// </para>
/// <para>
/// A timeout is not retried either. The caller asked for an answer within a budget; spending
/// that budget twice serves the caller worse than telling it the truth once.
/// </para>
/// </remarks>
public sealed class RetryOnceHandler : DelegatingHandler
{
    /// <summary>The total number of transport attempts this handler may make.</summary>
    public const int MaxAttempts = 2;

    /// <inheritdoc />
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        // The body is buffered before the first attempt, because a request whose content has
        // already been streamed cannot be sent again — and discovering that during the retry
        // would turn a recoverable blip into a confusing second failure.
        using var replay = await CloneAsync(request, cancellationToken).ConfigureAwait(false);

        try
        {
            return await base.SendAsync(request, cancellationToken).ConfigureAwait(false);
        }
        catch (HttpRequestException exception) when (IsOpaque(exception, cancellationToken))
        {
            return await base.SendAsync(replay, cancellationToken).ConfigureAwait(false);
        }
    }

    /// <summary>
    /// An opaque failure is one with no HTTP status and no cancellation: the connection never
    /// produced an answer.
    /// </summary>
    private static bool IsOpaque(HttpRequestException exception, CancellationToken cancellationToken) =>
        exception.StatusCode is null && !cancellationToken.IsCancellationRequested;

    private static async Task<HttpRequestMessage> CloneAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var clone = new HttpRequestMessage(request.Method, request.RequestUri)
        {
            Version = request.Version,
            VersionPolicy = request.VersionPolicy,
        };

        foreach (var header in request.Headers)
        {
            clone.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }

        foreach (var option in (IDictionary<string, object?>)request.Options)
        {
            clone.Options.Set(new HttpRequestOptionsKey<object?>(option.Key), option.Value);
        }

        if (request.Content is null) return clone;

        var bytes = await request.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
        var content = new ByteArrayContent(bytes);
        foreach (var header in request.Content.Headers)
        {
            content.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }

        clone.Content = content;
        return clone;
    }
}
