namespace AtomiCloud.Diene.ApiEngine.Calls;

/// <summary>
/// The per-call slot the transport writes a failed exchange into, so the classifier can see
/// the response body that a generated client has already turned into an exception.
/// </summary>
/// <remarks>
/// A generated SDK throws its own exception type and does not promise to carry the response
/// body on it. Reading the body from the pipeline instead is what keeps this engine
/// generator-agnostic: any client whose calls go through the tree's <c>HttpClient</c> is
/// classifiable, with no reflection over exception shapes and no dependency on a particular
/// generator's abstractions.
/// </remarks>
internal sealed class ApiCallCapture
{
    /// <summary>Gets the last failed exchange recorded during the call, if any.</summary>
    internal ApiFailure? Failure { get; private set; }

    /// <summary>Gets how many transport attempts the pipeline made.</summary>
    internal int Attempts { get; private set; }

    /// <summary>Records one failed exchange, replacing any earlier one.</summary>
    /// <remarks>
    /// Last write wins. A retried request produces two exchanges and it is the final one
    /// that describes the outcome the caller received.
    /// </remarks>
    internal void RecordFailure(ApiFailure failure) => Failure = failure;

    /// <summary>Counts one transport attempt.</summary>
    internal void RecordAttempt() => Attempts++;
}

/// <summary>
/// Binds an <see cref="ApiCallCapture" /> to the current asynchronous flow for the duration
/// of one wrapped call.
/// </summary>
/// <remarks>
/// The previous binding is restored on dispose rather than cleared, so a call made from
/// inside another wrapped call does not silently steal the outer call's capture.
/// </remarks>
internal sealed class ApiCallScope : IDisposable
{
    private static readonly AsyncLocal<ApiCallCapture?> Ambient = new();

    private readonly ApiCallCapture? _previous;
    private bool _disposed;

    internal ApiCallScope()
    {
        _previous = Ambient.Value;
        Capture = new ApiCallCapture();
        Ambient.Value = Capture;
    }

    /// <summary>Gets the capture bound for this scope.</summary>
    internal ApiCallCapture Capture { get; }

    /// <summary>Gets the capture bound to the current flow, or null outside a wrapped call.</summary>
    internal static ApiCallCapture? Active => Ambient.Value;

    /// <inheritdoc />
    public void Dispose()
    {
        if (_disposed) return;
        Ambient.Value = _previous;
        _disposed = true;
    }
}
