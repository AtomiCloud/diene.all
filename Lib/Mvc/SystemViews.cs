namespace AtomiCloud.Diene.ServerEngine.Mvc;

/// <summary>The build identity this instance reports about itself.</summary>
/// <param name="Landscape">The landscape this instance runs in.</param>
/// <param name="Platform">The owning platform.</param>
/// <param name="Service">The service name.</param>
/// <param name="Module">The module name.</param>
/// <param name="Version">The build version string.</param>
public sealed record SystemVersionView(
    string Landscape,
    string Platform,
    string Service,
    string Module,
    string Version);

/// <summary>The liveness answer, stamped with the instant it was produced.</summary>
/// <param name="Status">The serving status.</param>
/// <param name="CheckedAt">
/// When the answer was produced, on the wire as an RFC 3339 UTC instant.
/// </param>
public sealed record SystemHealthView(string Status, DateTimeOffset CheckedAt)
{
    /// <summary>The only status a serving instance reports; absence of a reply is the other case.</summary>
    public const string ServingStatus = "serving";
}
