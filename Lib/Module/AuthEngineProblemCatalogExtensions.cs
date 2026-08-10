using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.Diene.AuthEngine.Module;

/// <summary>Registers the auth-engine-owned problem contract with a consumer catalog.</summary>
// Consumer startup calls this extension; the library cannot call it on its own catalog.
// ReSharper disable once UnusedType.Global
public static class AuthEngineProblemCatalogExtensions
{
    /// <summary>Adds the generic app-handoff expiry problem at the configured redeem route.</summary>
    // ReSharper disable once UnusedMember.Global
    public static ProblemCatalogBuilder AddAtomiAuthEngineProblems(
        this ProblemCatalogBuilder catalog,
        AuthEngineConfig config)
    {
        ArgumentNullException.ThrowIfNull(catalog);
        ArgumentNullException.ThrowIfNull(config);

        return catalog.Add<AppHandoffExpired>(
            410,
            true,
            new ProblemEndpoint("POST", $"{config.Handoff.Mount}/redeem"));
    }
}
