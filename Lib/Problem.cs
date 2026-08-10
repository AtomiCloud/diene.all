using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems;

/// <summary>The RFC 9457 wire envelope with Diene's typed data and recoverability extensions.</summary>
public sealed record Problem
{
    /// <summary>Gets the URI identifying the problem contract.</summary>
    public string Type { get; init; } = "about:blank";

    /// <summary>Gets the short human-readable summary.</summary>
    public string Title { get; init; } = string.Empty;

    /// <summary>Gets the HTTP status code.</summary>
    public int Status { get; init; }

    /// <summary>Gets the instance-specific explanation.</summary>
    public string? Detail { get; init; }

    /// <summary>Gets the URI identifying the specific occurrence.</summary>
    public string? Instance { get; init; }

    /// <summary>Gets whether a caller may recover from this problem.</summary>
    public bool Recoverable { get; init; }

    /// <summary>Gets the typed problem payload.</summary>
    public JsonNode? Data { get; init; }

    /// <summary>Gets additional RFC 9457 extension members such as <c>traceId</c>.</summary>
    [JsonExtensionData]
    public IDictionary<string, JsonElement>? Extensions { get; init; }
}
