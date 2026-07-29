using AtomiCloud.Diene.Config;
using AtomiCloud.Diene.ServerEngine.Mvc;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

namespace AtomiCloud.DotnetBase.App.Modules.Info;

/// <summary>
/// The info endpoint. Both the liveness AND the readiness probe target this route, and it is
/// deliberately DEPENDENCY-BLIND: it reports that this process is serving, nothing more.
/// Dependency reachability belongs to the db-init path, so a database blip can never roll the
/// serving deployment.
/// </summary>
/// <param name="app">The bound service-tree identity.</param>
public sealed class InfoController(IOptions<AppOption> app) : AtomiController
{
    /// <summary>Reports service identity. Answers without touching any dependency.</summary>
    /// <returns>The service's own coordinates.</returns>
    [HttpGet("/")]
    public ActionResult<InfoView> Get()
    {
        var value = app.Value;
        return this.Ok(new InfoView(
            value.Landscape,
            value.Platform,
            value.Service,
            value.Module,
            value.Version));
    }
}

/// <summary>The info endpoint's response.</summary>
/// <param name="Landscape">Deployment environment.</param>
/// <param name="Platform">Product namespace.</param>
/// <param name="Service">This service.</param>
/// <param name="Module">This module.</param>
/// <param name="Version">The running version; matches the image tag and both chart versions.</param>
public sealed record InfoView(
    string Landscape,
    string Platform,
    string Service,
    string Module,
    string Version);
