using System.Text.RegularExpressions;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ServerEngine.Config;

/// <summary>
/// The service-tree coordinates and build version this service reports about itself.
/// </summary>
/// <remarks>
/// The same four coordinates key the published problem type URI, so they are validated to
/// the same segment shape here. A coordinate that passed this check but failed there would
/// let a service describe itself one way and address its problem documentation another.
/// </remarks>
public sealed partial class ServiceIdentityConfig
{
    private ServiceIdentityConfig(
        string landscape,
        string platform,
        string service,
        string module,
        string version)
    {
        this.Landscape = landscape;
        this.Platform = platform;
        this.Service = service;
        this.Module = module;
        this.Version = version;
    }

    /// <summary>Gets the landscape this instance runs in.</summary>
    public string Landscape { get; }

    /// <summary>Gets the owning platform.</summary>
    public string Platform { get; }

    /// <summary>Gets the service name.</summary>
    public string Service { get; }

    /// <summary>Gets the module name.</summary>
    public string Module { get; }

    /// <summary>Gets the build version string.</summary>
    public string Version { get; }

    /// <summary>Validates the coordinates and returns a typed failure rather than throwing.</summary>
    public static Result<ServiceIdentityConfig, ServerEngineConfigError> Create(
        string? landscape,
        string? platform,
        string? service,
        string? module,
        string? version)
    {
        var segments = new[]
        {
            ("identity.landscape", landscape),
            ("identity.platform", platform),
            ("identity.service", service),
            ("identity.module", module),
        };

        foreach (var (field, value) in segments)
        {
            if (string.IsNullOrWhiteSpace(value)) return new ServerEngineConfigError(field, "Value must not be blank.");

            if (!SegmentPattern().IsMatch(value.Trim()))
            {
                return new ServerEngineConfigError(
                    field,
                    "Value must start alphanumeric and contain only letters, digits, '.', '_', or '-'.");
            }
        }

        if (string.IsNullOrWhiteSpace(version))
        {
            return new ServerEngineConfigError("identity.version", "Version must not be blank.");
        }

        return new ServiceIdentityConfig(
            landscape!.Trim(),
            platform!.Trim(),
            service!.Trim(),
            module!.Trim(),
            version.Trim());
    }

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex SegmentPattern();
}
