namespace AtomiCloud.Diene.E2e;

/// <summary>The published assemblies held together by the E2e compatibility decision.</summary>
public static class PublishedPackageBundle
{
    /// <summary>Gets every runtime package assembly in the .NET family train.</summary>
    public static IReadOnlyList<string> RuntimeAssemblyNames { get; } =
    [
        "AtomiCloud.Diene.Result",
        "AtomiCloud.Diene.Interfaces",
        "AtomiCloud.Diene.CoreUtils",
        "AtomiCloud.Diene.Config",
        "AtomiCloud.Diene.Problems",
        "AtomiCloud.Diene.Otel",
        "AtomiCloud.Diene.AuthEngine",
        "AtomiCloud.Diene.StandardConfig",
        "AtomiCloud.Diene.ApiEngine",
        "AtomiCloud.Diene.ServerEngine",
    ];

    /// <summary>Gets the nine real TestHelper assemblies; CoreUtils deliberately has none.</summary>
    public static IReadOnlyList<string> TestHelperAssemblyNames { get; } =
    [
        "AtomiCloud.Diene.Result.TestHelper",
        "AtomiCloud.Diene.Interfaces.TestHelper",
        "AtomiCloud.Diene.Config.TestHelper",
        "AtomiCloud.Diene.Problems.TestHelper",
        "AtomiCloud.Diene.Otel.TestHelper",
        "AtomiCloud.Diene.AuthEngine.TestHelper",
        "AtomiCloud.Diene.StandardConfig.TestHelper",
        "AtomiCloud.Diene.ApiEngine.TestHelper",
        "AtomiCloud.Diene.ServerEngine.TestHelper",
    ];
}
