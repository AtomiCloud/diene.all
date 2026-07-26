using System.Text.RegularExpressions;

namespace AtomiCloud.Diene.Problems;

/// <summary>Builds the single canonical type URI for a registered problem.</summary>
public interface IProblemTypeUriBuilder
{
    /// <summary>Builds a problem type URI from its version and wire identifier.</summary>
    Uri Build(string version, string id);
}

/// <summary>Validates ErrorPortal inputs and builds versioned problem type URIs.</summary>
public sealed class ProblemTypeUriBuilder : IProblemTypeUriBuilder
{
    private static readonly Regex SegmentPattern = new(
        "^[A-Za-z0-9][A-Za-z0-9._-]*$",
        RegexOptions.CultureInvariant);

    private static readonly Regex VersionPattern = new(
        "^v[0-9]+$",
        RegexOptions.CultureInvariant);

    private static readonly Regex ProblemIdPattern = new(
        "^[a-z][a-z0-9_]*$",
        RegexOptions.CultureInvariant);

    private readonly ErrorPortalConfig _config;

    /// <summary>Creates a builder from plain, config-library-independent values.</summary>
    public ProblemTypeUriBuilder(ErrorPortalConfig config)
    {
        _config = config ?? throw new ArgumentNullException(nameof(config));
        ValidateScheme(config.Scheme);
        ValidateHost(config.Scheme, config.Host);
        ArgumentNullException.ThrowIfNull(config.Identity);
        ValidateSegment(nameof(config.Identity.Landscape), config.Identity.Landscape, SegmentPattern);
        ValidateSegment(nameof(config.Identity.Platform), config.Identity.Platform, SegmentPattern);
        ValidateSegment(nameof(config.Identity.Service), config.Identity.Service, SegmentPattern);
        ValidateSegment(nameof(config.Identity.Module), config.Identity.Module, SegmentPattern);
    }

    /// <inheritdoc />
    public Uri Build(string version, string id)
    {
        ValidateVersion(version);
        ValidateId(id);
        var identity = _config.Identity;
        return new Uri(
            $"{_config.Scheme}://{_config.Host}/docs/{identity.Landscape}/{identity.Platform}/{identity.Service}/{identity.Module}/{version}/{id}",
            UriKind.Absolute);
    }

    internal static void ValidateVersion(string version) =>
        ValidateSegment(nameof(version), version, VersionPattern);

    internal static void ValidateId(string id) =>
        ValidateSegment(nameof(id), id, ProblemIdPattern);

    private static void ValidateScheme(string scheme)
    {
        if (scheme is not "http" and not "https")
            throw new ArgumentOutOfRangeException(nameof(scheme), scheme, "ErrorPortal scheme must be http or https.");
    }

    private static void ValidateHost(string scheme, string host)
    {
        if (string.IsNullOrEmpty(host) || host.Trim() != host || host.IndexOfAny(['/', '\\', ' ', '@', '?', '#']) >= 0)
            throw new ArgumentOutOfRangeException(nameof(host), host, "ErrorPortal host must be a canonical host or host:port.");

        if (!Uri.TryCreate($"{scheme}://{host}/", UriKind.Absolute, out var origin) ||
            origin.Authority != host ||
            origin.UserInfo.Length != 0 ||
            origin.AbsolutePath != "/" ||
            origin.Query.Length != 0 ||
            origin.Fragment.Length != 0)
        {
            throw new ArgumentOutOfRangeException(nameof(host), host, "ErrorPortal host must be a canonical host or host:port.");
        }
    }

    private static void ValidateSegment(string name, string value, Regex pattern)
    {
        if (value is null || !pattern.IsMatch(value))
            throw new ArgumentOutOfRangeException(name, value, $"{name} must match {pattern}.");
    }
}
