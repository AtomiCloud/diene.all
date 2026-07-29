using AtomiCloud.Diene.E2e.Garden;

namespace AtomiCloud.Diene.E2e.Drivers;

/// <summary>Parses the explicit SIT_DRIVER venue selector.</summary>
public static class SitDriverSelection
{
    /// <summary>Gets the environment variable consumed by service SIT entry points.</summary>
    public const string EnvironmentVariable = "SIT_DRIVER";

    /// <summary>Resolves an explicit selector without silently choosing a venue.</summary>
    public static SitDriverKind Resolve(string? value) =>
        value?.Trim().ToLowerInvariant() switch
        {
            "inprocess" => SitDriverKind.InProcess,
            "garden" => SitDriverKind.Garden,
            _ => throw new E2eHarnessException(
                $"{EnvironmentVariable} must be either inprocess or garden"),
        };
}
