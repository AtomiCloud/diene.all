using AtomiCloud.Diene.ApiEngine.Calls;

namespace AtomiCloud.Diene.ApiEngine.Transport;

/// <summary>
/// Records what a failed exchange actually returned, so the classifier can see a response
/// body that a generated client has already consumed and turned into an exception.
/// </summary>
/// <remarks>
/// The body is buffered rather than replaced. Buffered content can be read any number of
/// times, so the generated client still reads exactly the bytes it would have read — a
/// substituted <c>HttpContent</c> would silently drop the original content headers.
/// </remarks>
public sealed class FailureCaptureHandler : DelegatingHandler
{
    /// <inheritdoc />
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var capture = ApiCallScope.Active;
        capture?.RecordAttempt();

        var response = await base.SendAsync(request, cancellationToken).ConfigureAwait(false);

        // Nothing to record outside a wrapped call, and nothing to record for a success:
        // the caller already has its typed value in that case.
        if (capture is null || response.IsSuccessStatusCode) return response;

        await response.Content.LoadIntoBufferAsync(cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        capture.RecordFailure(new ApiFailure(
            (int)response.StatusCode,
            response.Content.Headers.ContentType?.MediaType,
            body));
        return response;
    }
}
