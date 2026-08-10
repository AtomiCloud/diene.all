using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.ServerEngine.Config;
using Microsoft.AspNetCore.Mvc;

namespace AtomiCloud.Diene.ServerEngine.Mvc;

/// <summary>
/// The system endpoints every Diene service exposes: what this build is, and whether it is
/// serving.
/// </summary>
/// <remarks>
/// The route is fixed rather than configurable. These two paths are read by tooling that has
/// no access to a service's configuration — a probe, a deployment gate, an operator — so a
/// per-service mount would make them undiscoverable, which is the opposite of the point.
/// </remarks>
[Route("system")]
public sealed class SystemController(ServerEngineConfig config, IAuthClock clock) : AtomiController
{
    private readonly ServerEngineConfig _config = config ?? throw new ArgumentNullException(nameof(config));
    private readonly IAuthClock _clock = clock ?? throw new ArgumentNullException(nameof(clock));

    /// <summary>Reports the service-tree coordinates and build version of this instance.</summary>
    [HttpGet("version")]
    public ActionResult<SystemVersionView> Version()
    {
        var identity = this._config.Identity;
        return this.Ok(
            new SystemVersionView(
                identity.Landscape,
                identity.Platform,
                identity.Service,
                identity.Module,
                identity.Version));
    }

    /// <summary>Reports that this instance is serving, stamped with the instant it answered.</summary>
    [HttpGet("health")]
    public ActionResult<SystemHealthView> Health() =>
        this.Ok(new SystemHealthView(SystemHealthView.ServingStatus, this._clock.UtcNow));
}
