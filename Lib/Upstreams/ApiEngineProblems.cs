using AtomiCloud.Diene.Problems;

namespace AtomiCloud.Diene.ApiEngine.Upstreams;

/// <summary>
/// The two problems this engine can originate, with the statuses a consumer should register
/// them under.
/// </summary>
/// <remarks>
/// Status is catalog registration data, so the catalog is where it is finally declared. These
/// constants exist so the engine and the consumer's catalog cannot disagree: the classifier
/// stamps the envelope with the same value the registration helper hands the catalog.
/// </remarks>
public static class ApiEngineProblems
{
    /// <summary>The status for an upstream that answered with a non-problem JSON failure.</summary>
    /// <remarks>
    /// 502: this service asked another service and got back something it cannot honour, which
    /// is a bad gateway rather than a fault of the caller.
    /// </remarks>
    public const int UpstreamRejectedStatus = 502;

    /// <summary>The status for an upstream call that produced no interpretable answer.</summary>
    /// <remarks>
    /// 504: the exchange did not complete usefully. One status for the whole type, so a
    /// catalog row is unambiguous — the specifics live in the payload, not in the status.
    /// </remarks>
    public const int UpstreamTransportFailureStatus = 504;

    /// <summary>An upstream that answered is not retryable — it will answer the same way again.</summary>
    public const bool UpstreamRejectedRecoverable = false;

    /// <summary>An exchange that produced no answer may succeed on a later attempt.</summary>
    public const bool UpstreamTransportFailureRecoverable = true;

    /// <summary>
    /// Registers both problems in a consumer's catalog with the statuses and recoverability
    /// above.
    /// </summary>
    /// <remarks>
    /// Offered as one call so a consumer cannot register one and forget the other, which
    /// would leave half of this engine's failures rendering as <c>about:blank</c>. The
    /// classifier stamps envelopes from these same constants, so the catalog row and the
    /// wire value cannot drift apart.
    /// </remarks>
    public static ProblemCatalogBuilder AddApiEngineProblems(this ProblemCatalogBuilder catalog)
    {
        ArgumentNullException.ThrowIfNull(catalog);
        return catalog
            .Add<UpstreamRejected>(UpstreamRejectedStatus, UpstreamRejectedRecoverable)
            .Add<UpstreamTransportFailure>(UpstreamTransportFailureStatus, UpstreamTransportFailureRecoverable);
    }
}
