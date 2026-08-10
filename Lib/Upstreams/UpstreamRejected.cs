using System.ComponentModel;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.Diene.ApiEngine.Upstreams;

/// <summary>
/// An upstream returned a failure whose body is well-formed JSON but is not a problem
/// envelope.
/// </summary>
/// <remarks>
/// This is a DIFFERENT condition from an unreachable upstream, and the distinction is the
/// whole point: this call reached the service and got an answer, so retrying it will
/// produce the same answer. The upstream's status is preserved and its body is carried
/// verbatim, because a caller diagnosing a contract mismatch needs the bytes that did not
/// match, not a summary of them.
/// <para>
/// The payload members are <c>init</c> rather than get-only so the serialized <c>data</c>
/// extension round-trips: a test or a downstream reader that decodes this payload gets the
/// values back, instead of a silently defaulted instance.
/// </para>
/// </remarks>
[Description("An upstream returned a JSON failure body that is not a problem envelope.")]
public sealed class UpstreamRejected : IDomainProblem
{
    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public UpstreamRejected()
    {
    }

    /// <summary>Creates a populated upstream-rejected problem.</summary>
    public UpstreamRejected(string detail, string upstream, int upstreamStatus, string? contentType, string body)
    {
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));
        Upstream = upstream ?? throw new ArgumentNullException(nameof(upstream));
        UpstreamStatus = upstreamStatus;
        ContentType = contentType ?? string.Empty;
        Body = body ?? throw new ArgumentNullException(nameof(body));
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "upstream_rejected";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Upstream Rejected";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets the LPSM address of the upstream that answered.</summary>
    [Description("The LPSM address of the upstream that returned the failure.")]
    public string Upstream { get; init; } = string.Empty;

    /// <summary>Gets the HTTP status the upstream returned.</summary>
    [Description("The HTTP status code the upstream returned.")]
    public int UpstreamStatus { get; init; }

    /// <summary>Gets the media type of the upstream's body.</summary>
    [Description("The media type of the upstream response body.")]
    public string ContentType { get; init; } = string.Empty;

    /// <summary>Gets the upstream's response body verbatim.</summary>
    [Description("The upstream response body, carried verbatim.")]
    public string Body { get; init; } = string.Empty;
}
