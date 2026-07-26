using System.Globalization;
using AtomiCloud.Diene.Config.Env;
using AtomiCloud.Diene.Config.Yaml;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.Diene.Config;

/// <summary>
/// Composes the C0 §3 layer stack: base YAML → sparse landscape overlay → prefixed
/// environment LAST.
/// </summary>
public static class AtomiConfigExtensions
{
    /// <summary>Adds all three layers of the precedence contract, in order.</summary>
    /// <exception cref="ArgumentException">
    /// The env prefix is blank, or reload-on-change was requested — hot reload is deferred
    /// family-wide in v1 and silently ignoring the request would be worse than refusing it.
    /// </exception>
    public static IConfigurationBuilder AddAtomiConfig(this IConfigurationBuilder builder, AtomiConfigSource source)
    {
        ArgumentNullException.ThrowIfNull(builder);
        ArgumentNullException.ThrowIfNull(source);

        if (string.IsNullOrWhiteSpace(source.EnvPrefix))
            throw new ArgumentException(
                "EnvPrefix is required: the config library bakes no default prefix, the app supplies one.",
                nameof(source));

        if (source.ReloadOnChange)
            throw new ArgumentException(
                "ReloadOnChange is not supported in v1: hot reload is deferred family-wide.",
                nameof(source));

        builder.AddAtomiYamlFile(source.BaseFile, optional: false);

        var landscape = string.IsNullOrWhiteSpace(source.Landscape)
            ? Environment.GetEnvironmentVariable(AtomiConfigSource.LandscapeVariable)
            : source.Landscape;

        if (!string.IsNullOrWhiteSpace(landscape))
            builder.AddAtomiYamlFile(
                string.Format(CultureInfo.InvariantCulture, source.LandscapePattern, landscape),
                optional: true);

        return builder.AddAtomiEnvironmentVariables(source.EnvPrefix);
    }

    /// <summary>Adds one YAML layer whose keys are normalized to the canonical C0 spelling.</summary>
    public static IConfigurationBuilder AddAtomiYamlFile(
        this IConfigurationBuilder builder,
        string path,
        bool optional)
    {
        ArgumentNullException.ThrowIfNull(builder);
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        var source = new YamlConfigurationSource
        {
            Path = path,
            Optional = optional,
            ReloadOnChange = false,
        };

        // Splits an absolute path into a provider rooted at its directory plus a bare file
        // name. Without it an absolute path is joined onto the base directory and the layer
        // is looked for at a nonsense location.
        source.ResolveFileProvider();

        return builder.Add(source);
    }

    /// <summary>Adds the prefixed environment layer, read from the live process environment.</summary>
    public static IConfigurationBuilder AddAtomiEnvironmentVariables(this IConfigurationBuilder builder, string prefix) =>
        builder.AddAtomiEnvironmentVariables(prefix, AtomiEnvironmentSource.ProcessEnvironment());

    /// <summary>
    /// Adds the prefixed environment layer, read from an explicit set of variables rather than
    /// the process environment — the seam consumers fake in tests.
    /// </summary>
    public static IConfigurationBuilder AddAtomiEnvironmentVariables(
        this IConfigurationBuilder builder,
        string prefix,
        IEnumerable<KeyValuePair<string, string?>> variables)
    {
        ArgumentNullException.ThrowIfNull(builder);
        ArgumentException.ThrowIfNullOrWhiteSpace(prefix);
        ArgumentNullException.ThrowIfNull(variables);

        return builder.Add(new AtomiEnvironmentSource { Prefix = prefix, Variables = variables });
    }
}
