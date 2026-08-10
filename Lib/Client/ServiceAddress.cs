using System.Text.RegularExpressions;
using AtomiCloud.Diene.ApiEngine.Config;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ApiEngine.Client;

/// <summary>
/// An upstream's address in the service tree. The landscape is implied by the deployment
/// environment and is therefore absent: a client never addresses another landscape, so
/// carrying a landscape here would create a way to express a call that must not exist.
/// </summary>
public sealed record ServiceAddress
{
    private static readonly Regex SegmentPattern = new(
        "^[a-z][a-z0-9-]*$",
        RegexOptions.CultureInvariant,
        TimeSpan.FromSeconds(1));

    private ServiceAddress(string platform, string service, string module)
    {
        Platform = platform;
        Service = service;
        Module = module;
    }

    /// <summary>Gets the platform segment.</summary>
    public string Platform { get; }

    /// <summary>Gets the service segment.</summary>
    public string Service { get; }

    /// <summary>Gets the module segment.</summary>
    public string Module { get; }

    /// <summary>
    /// Validates and constructs an address. Segments are lowercase service-tree names, so
    /// a mistyped upstream is rejected at composition rather than becoming a keyed-service
    /// lookup that silently finds nothing.
    /// </summary>
    public static Result<ServiceAddress, ApiConfigError> Create(string? platform, string? service, string? module)
    {
        var validated = Validate(nameof(platform), platform)
            .Then(p => Validate(nameof(service), service).Map(s => (Platform: p, Service: s)))
            .Then(pair => Validate(nameof(module), module)
                .Map(m => new ServiceAddress(pair.Platform, pair.Service, m)));
        return validated;
    }

    /// <summary>Parses the canonical <c>platform.service.module</c> key form.</summary>
    public static Result<ServiceAddress, ApiConfigError> Parse(string? key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            return new ApiConfigError("address", "Address must not be blank.");
        }

        var parts = key.Trim().Split('.');
        return parts.Length != 3
            ? new ApiConfigError("address", $"Address '{key}' must have exactly three dot-separated segments.")
            : Create(parts[0], parts[1], parts[2]);
    }

    /// <summary>Renders the keyed-service key: <c>platform.service.module</c>.</summary>
    public override string ToString() => $"{Platform}.{Service}.{Module}";

    private static Result<string, ApiConfigError> Validate(string field, string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return new ApiConfigError(field, "Segment must not be blank.");
        }

        var trimmed = value.Trim();
        return SegmentPattern.IsMatch(trimmed)
            ? trimmed
            : new ApiConfigError(field, $"Segment '{trimmed}' must be lowercase alphanumeric with hyphens.");
    }
}
