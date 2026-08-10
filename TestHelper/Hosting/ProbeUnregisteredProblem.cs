using System.ComponentModel;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;

/// <summary>
/// A typed problem deliberately absent from every catalog, so the unregistered path is reachable.
/// </summary>
/// <remarks>
/// Forgetting to register a problem is silent until a caller hits it, and what happens then — 500
/// with an <c>about:blank</c> type rather than a documentation URI that would 404 — is behaviour a
/// consumer should be able to pin. Reaching it needs a problem that is guaranteed never to be
/// registered, which no real catalog entry can be.
/// </remarks>
[Description("A probe problem intentionally absent from every catalog.")]
public sealed class ProbeUnregisteredProblem : IDomainProblem
{
    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "probe_unregistered";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Probe Unregistered";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail => "This problem is never registered in a catalog.";

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";
}
