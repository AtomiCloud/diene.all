using System.Collections;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.Diene.Config.Env;

/// <summary>The prefixed environment layer, applied LAST in the C0 §3 precedence order.</summary>
internal sealed class AtomiEnvironmentSource : IConfigurationSource
{
    /// <summary>The required prefix identifying the variables that belong to this app.</summary>
    public required string Prefix { get; init; }

    /// <summary>
    /// The variables to read. Supplied explicitly by tests and fakes; defaults to the real
    /// process environment.
    /// </summary>
    public required IEnumerable<KeyValuePair<string, string?>> Variables { get; init; }

    public IConfigurationProvider Build(IConfigurationBuilder builder) => new AtomiEnvironmentProvider(this);

    /// <summary>Reads the live process environment as name/value pairs.</summary>
    internal static IEnumerable<KeyValuePair<string, string?>> ProcessEnvironment()
    {
        foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
            yield return new KeyValuePair<string, string?>((string)entry.Key, entry.Value as string);
    }
}

/// <summary>
/// Projects prefixed environment variables onto canonical configuration keys.
/// </summary>
/// <remarks>
/// <c>__</c> is the nesting separator, so <c>ATOMI_ERROR_PORTAL__ENABLED</c> becomes
/// <c>errorportal:enabled</c> and overrides the same key a YAML <c>error_portal.enabled</c>
/// wrote. List elements arrive as indexed keys (<c>FOO__0</c>, <c>FOO__1</c>) which the
/// configuration binder already understands as a collection — there is no JSON-in-env and
/// no comma encoding.
/// </remarks>
internal sealed class AtomiEnvironmentProvider(AtomiEnvironmentSource source) : ConfigurationProvider
{
    private const string NestingSeparator = "__";

    public override void Load()
    {
        var data = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        foreach (var (name, value) in source.Variables)
        {
            if (ToConfigurationKey(name, source.Prefix) is not { } key) continue;
            data[key] = value;
        }

        Data = data;
    }

    /// <summary>
    /// Maps one environment variable name onto its canonical configuration key, or
    /// <see langword="null" /> when the variable does not belong to this app.
    /// </summary>
    internal static string? ToConfigurationKey(string name, string prefix)
    {
        if (!name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return null;

        var body = name[prefix.Length..];

        // The bare prefix is not a key, and neither is a name whose every segment is empty.
        var segments = body.Split(NestingSeparator);
        if (segments.Any(string.IsNullOrEmpty)) return null;

        return string.Join(ConfigurationPath.KeyDelimiter, segments.Select(ConfigKey.Segment));
    }
}
