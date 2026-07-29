using AtomiCloud.Diene.ApiEngine.Upstreams;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.DotnetBase.App.Error;

/// <summary>
/// The service's problem catalog. Registration is explicit — never implicit scanning — so the
/// exported Problem CR and the wire envelope describe exactly the same set.
/// </summary>
public static class ServiceProblems
{
    /// <summary>
    /// Registers the portable baseline, the api-engine's upstream problems, and this service's
    /// own domain problems.
    /// </summary>
    /// <param name="catalog">The catalog builder supplied by the problems package.</param>
    /// <returns>The same builder.</returns>
    public static ProblemCatalogBuilder AddServiceProblems(this ProblemCatalogBuilder catalog)
    {
        ArgumentNullException.ThrowIfNull(catalog);

        catalog.AddBaseline();
        catalog.AddApiEngineProblems();

        // ── Domain problems (illustrative sample) — replace with your domain's ──
        catalog.Add<NoteTitleConflict>(
            status: StatusCodes.Status409Conflict,
            recoverable: true,
            endpoints: [new ProblemEndpoint("POST", "/api/v1/notes"), new ProblemEndpoint("PUT", "/api/v1/notes/{id}")]);
        // ── End domain problems ──

        return catalog;
    }
}
