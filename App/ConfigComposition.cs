using AtomiCloud.Diene.Config;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// The composition root a real service copies: declare the layers, register the blocks, let
/// startup validation decide whether the process is allowed to run.
/// </summary>
public static class ConfigComposition
{
    /// <summary>The env prefix this app configures. The library bakes no default.</summary>
    public const string EnvPrefix = "ATOMI_";

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
        // The engine's own validator runs first; the service layers its own rule on top of the
        // returned builder, which is what the OptionsBuilder return value is for.
        services
            .RegisterOption<ErrorPortalOption, ErrorPortalOptionValidator>(ErrorPortalOption.Key)
            .Validate(
                option => option.RetryHosts.Count <= 8,
                "Config 'ErrorPortal:RetryHosts' is invalid: this service accepts at most eight fallback hosts");

        return services.AddAtomiServiceTree();
    }

    /// <summary>Builds a provider over a merged configuration with every block registered.</summary>
    public static ServiceProvider Provider(IConfiguration configuration)
    {
        var services = new ServiceCollection();
        services.AddSingleton(configuration);
        return services.Register().BuildServiceProvider();
    }

    /// <summary>The root schema this service publishes, assembled from the registered blocks.</summary>
    public static IConfigSchemaRegistry Registry()
    {
        IConfigSchemaRegistry registry = new ConfigSchemaRegistry();
        registry.Register<AppOption>(AppOption.Key);
        registry.Register<ErrorPortalOption>(ErrorPortalOption.Key);
        return registry;
    }
}
