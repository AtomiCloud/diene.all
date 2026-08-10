using System.ComponentModel.DataAnnotations;

namespace AtomiCloud.Diene.ApiEngine.Config;

/// <summary>
/// The engine-owned <c>HttpClient</c> configuration block: one entry per upstream backend,
/// keyed by its LPSM address. This schema is exported beside the client-tree code that
/// reads it, and a service composes it into its own configuration root — the config
/// library remains the sole merger and validator.
/// </summary>
/// <remarks>
/// Each entry carries exactly ONE hostname. Physical or per-cluster URL lists, circuit
/// breakers, and failover ladders are deliberately absent: the gray-zone DNS A-set is the
/// only thing that moves underneath a base address, so a client-side list would be a
/// second, staler copy of a routing decision that is not the client's to make.
/// </remarks>
public sealed class HttpClientOption
{
    /// <summary>The conventional configuration section key.</summary>
    public const string Key = "HttpClient";

    /// <summary>Gets or sets the single base address for this upstream.</summary>
    [Required]
    [Url]
    public string BaseAddress { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the request timeout as an ISO 8601 duration, per the C0 serialization
    /// contract. A duration is a wire value like any other, so it is spelled the same way
    /// here as it would be in a payload.
    /// </summary>
    [Required]
    public string Timeout { get; set; } = "PT30S";

    /// <summary>
    /// Gets or sets the auth-engine resource indicator. When present, requests to this
    /// upstream carry a bearer token acquired for THIS resource; when absent, the upstream
    /// is called unauthenticated.
    /// </summary>
    public string? AuthResource { get; set; }

    /// <summary>Gets the scopes requested alongside <see cref="AuthResource" />.</summary>
    /// <remarks>
    /// Get-only and mutable in place: the configuration binder populates an existing
    /// collection, and a get-only collection avoids handing callers a settable array whose
    /// contents they could swap after validation.
    /// </remarks>
    public IList<string> AuthScopes { get; } = [];

    /// <summary>
    /// Gets or sets whether the dormant rescue-routing trip point is armed for this
    /// upstream.
    /// </summary>
    /// <remarks>
    /// The router itself does not live here — this flag only decides whether a hard
    /// connect failure is reported as rescuable. Server runtimes leave it off, because
    /// their rescue is a redeploy rather than an address hunt.
    /// </remarks>
    public bool RescueRoutingEnabled { get; set; }
}
