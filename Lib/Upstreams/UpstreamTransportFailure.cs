using System.ComponentModel;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.Diene.ApiEngine.Upstreams;

/// <summary>
/// A call to an upstream did not produce an interpretable answer: no response at all
/// (network, DNS, TLS, timeout, cancellation), or a response whose body could not be read
/// as JSON — including a bare status with no body at all.
/// </summary>
/// <remarks>
/// Deliberately a different problem type from <see cref="UpstreamRejected" />. That one
/// means "the service answered and said no"; this one means "there is no answer to read".
/// Only this one is recoverable, and conflating them is what makes a caller retry a
/// rejection forever or give up on a blip.
/// <para>
/// The payload members are <c>init</c> rather than get-only so the serialized <c>data</c>
/// extension round-trips: a test or a downstream reader that decodes this payload gets the
/// values back, instead of a silently defaulted instance.
/// </para>
/// </remarks>
[Description("An upstream call produced no interpretable response.")]
public sealed class UpstreamTransportFailure : IDomainProblem
{
    /// <summary>The snippet length kept from an unreadable body.</summary>
    /// <remarks>
    /// Bounded on purpose: an HTML error page or a truncated stream can be arbitrarily
    /// long, and a problem payload that can grow without limit is a way to turn one bad
    /// upstream into a logging incident.
    /// </remarks>
    public const int BodySnippetLength = 512;

    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public UpstreamTransportFailure()
    {
    }

    /// <summary>Creates a populated transport-failure problem.</summary>
    public UpstreamTransportFailure(
        string detail,
        string upstream,
        int? upstreamStatus,
        string? contentType,
        string? bodySnippet,
        int attempts,
        bool rescuable)
    {
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));
        Upstream = upstream ?? throw new ArgumentNullException(nameof(upstream));
        UpstreamStatus = upstreamStatus;
        ContentType = contentType ?? string.Empty;
        BodySnippet = Snip(bodySnippet);
        Attempts = attempts;
        Rescuable = rescuable;
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "upstream_transport_failure";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Upstream Transport Failure";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets the LPSM address of the upstream that was called.</summary>
    [Description("The LPSM address of the upstream that was called.")]
    public string Upstream { get; init; } = string.Empty;

    /// <summary>Gets the HTTP status when one was received, or null when none was.</summary>
    /// <remarks>
    /// Null is load-bearing: it is the difference between "the connection never produced a
    /// status" and "a status arrived that we could not act on".
    /// </remarks>
    [Description("The HTTP status code, when a response was received at all.")]
    public int? UpstreamStatus { get; init; }

    /// <summary>Gets the media type of whatever body arrived.</summary>
    [Description("The media type of the response body, when one arrived.")]
    public string ContentType { get; init; } = string.Empty;

    /// <summary>Gets a bounded prefix of the unreadable body.</summary>
    [Description("A bounded prefix of the response body that could not be interpreted.")]
    public string BodySnippet { get; init; } = string.Empty;

    /// <summary>Gets how many transport attempts were made, including the retry.</summary>
    [Description("How many transport attempts were made, including the single retry.")]
    public int Attempts { get; init; }

    /// <summary>
    /// Gets whether the rescue-routing trip point is armed for this upstream.
    /// </summary>
    /// <remarks>
    /// api-engine only reports this. The router that would act on it — catalog lookup,
    /// suffix allowlist, budgeted candidate scan — lives in the frontend utilities, and
    /// putting it here would make every server runtime carry a rescue path it must not use.
    /// </remarks>
    [Description("Whether the dormant rescue-routing trip point is armed for this upstream.")]
    public bool Rescuable { get; init; }

    private static string Snip(string? body)
    {
        if (string.IsNullOrEmpty(body)) return string.Empty;
        return body.Length <= BodySnippetLength ? body : body[..BodySnippetLength];
    }
}
