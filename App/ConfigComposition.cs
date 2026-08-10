using AtomiCloud.Diene.Config;
using AtomiCloud.Diene.StandardConfig.Presets;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// The composition root a real service copies: declare the layers, compose the root schema
/// from the blocks this service needs, and let startup validation decide whether the process
/// is allowed to run.
/// </summary>
/// <remarks>
/// Note what is NOT here. This app never merges or validates anything itself — the config lib
/// is the sole merger and validator — and standard-config never loads a file. The service
/// composes: one line per infra preset, one per engine block, plus its own keys.
/// </remarks>
public static class ConfigComposition
{
    /// <summary>The env prefix this app configures. The library bakes no default.</summary>
    public const string EnvPrefix = "ATOMI_";

    /// <summary>The presets this demo service composes.</summary>
    public const StandardConfigPreset Presets = StandardConfigPreset.All;

    /// <summary>Config files ship next to the binary, so the app runs from any directory.</summary>
    public static AtomiConfigSource Source(string landscape) => new()
    {
        BaseFile = Path.Combine(AppContext.BaseDirectory, "Config", "settings.yaml"),
        LandscapePattern = Path.Combine(AppContext.BaseDirectory, "Config", "settings.{0}.yaml"),
        Landscape = landscape,
        EnvPrefix = EnvPrefix,
        ReloadOnChange = false,
    };

    /// <summary>Builds the merged configuration the way a deployed service does.</summary>
    public static IConfiguration Build(string landscape) =>
        new ConfigurationBuilder().AddAtomiConfig(Source(landscape)).Build();

    /// <summary>
    /// Builds the merged configuration from an explicit environment rather than the process
    /// one, so a test can assert on precedence without mutating global state.
    /// </summary>
    public static IConfiguration Build(string landscape, IEnumerable<KeyValuePair<string, string?>> environment)
    {
        var source = Source(landscape);
        return new ConfigurationBuilder()
            .AddAtomiYamlFile(source.BaseFile, optional: false)
            .AddAtomiYamlFile(
                string.Format(System.Globalization.CultureInfo.InvariantCulture, source.LandscapePattern, landscape),
                optional: true)
            .AddAtomiEnvironmentVariables(source.EnvPrefix, environment)
            .Build();
    }

    /// <summary>Registers every block this service composes into its root config.</summary>
    public static IServiceCollection Register(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);
        return services.AddStandardConfigs(Presets).AddAtomiServiceTree();
    }

    /// <summary>Builds a provider over a merged configuration with every block registered.</summary>
    public static ServiceProvider Provider(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var services = new ServiceCollection();
        services.AddSingleton(configuration);
        return services.Register().BuildServiceProvider();
    }

    /// <summary>The root schema this service publishes, assembled from the registered blocks.</summary>
    public static IConfigSchemaRegistry Registry()
    {
        IConfigSchemaRegistry registry = new ConfigSchemaRegistry();
        registry.Register<AppOption>(AppOption.Key);
        registry.Register<PostgresBlock>(PostgresOption.Key);
        registry.Register<CacheBlock>(CacheOption.Key);
        registry.Register<KvBlock>(KvOption.Key);
        registry.Register<StorageBlock>(StorageOption.Key);
        return registry;
    }
}
