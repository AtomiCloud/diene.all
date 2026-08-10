using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Config;

/// <summary>Settings for the enable-able app-handoff controller module.</summary>
public sealed class HandoffConfig
{
    /// <summary>The mount path used when a consumer does not configure one.</summary>
    public const string DefaultMount = "/app-handoff";

    private HandoffConfig(string mount) => this.Mount = mount;

    /// <summary>Gets the absolute path the handoff endpoints are mounted at.</summary>
    public string Mount { get; }

    /// <summary>Creates the settings with the default mount path.</summary>
    public static HandoffConfig Default { get; } = new(DefaultMount);

    /// <summary>
    /// Validates a consumer-supplied mount path. Rejects relative paths, empty segments,
    /// dot-traversal, whitespace, and anything carrying a query, fragment, or backslash,
    /// so a mount cannot silently escape the intended prefix.
    /// </summary>
    public static Result<HandoffConfig, ConfigError> Create(string? mount)
    {
        if (string.IsNullOrWhiteSpace(mount)) return new ConfigError("handoff.mount", "Mount must not be blank.");

        var value = mount.Trim();

        if (!value.StartsWith('/')) return new ConfigError("handoff.mount", "Mount must be an absolute path.");

        if (value.Contains("//", StringComparison.Ordinal))
        {
            return new ConfigError("handoff.mount", "Mount must not contain an empty segment.");
        }

        if (value.IndexOfAny(['\\', '?', '#', '%']) >= 0)
        {
            return new ConfigError(
                "handoff.mount",
                "Mount must not contain a backslash, query, fragment, or percent-encoding.");
        }

        if (value.Any(char.IsWhiteSpace))
        {
            return new ConfigError("handoff.mount", "Mount must not contain whitespace.");
        }

        var segments = value.Split('/');
        if (segments.Any(segment => segment is "." or ".."))
        {
            return new ConfigError("handoff.mount", "Mount must not contain dot-path traversal segments.");
        }

        return new HandoffConfig(value);
    }
}
