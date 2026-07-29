using AtomiCloud.Diene.Config;
using AtomiCloud.Diene.Otel;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.StandardConfig.Presets;
using AtomiCloud.DotnetBase.App.Options;
using Microsoft.Extensions.Options;

namespace AtomiCloud.DotnetBase.App.StartUp.Registration;

/// <summary>
/// The configuration layer of the composition root: declare the three layers, then register
/// every block so the FINAL merged layer is what gets validated at <c>ValidateOnStart</c>.
/// </summary>
public static class ConfigurationRegistration
{
    /// <summary>Environment-variable prefix. The prefix is an app-level decision, never a library's.</summary>
    public const string EnvironmentPrefix = "ATOMI_";

    /// <summary>Path to the base layer, relative to the content root.</summary>
    public const string BaseFile = "Config/settings.yaml";

    /// <summary>Pattern for the sparse landscape overlay.</summary>
    public const string LandscapePattern = "Config/settings.{0}.yaml";

    /// <summary>
    /// Adds the layered configuration source. Precedence is base, then landscape overlay, then
    /// environment — which is <c>IConfiguration</c> provider ordering, not a merge engine.
    /// </summary>
    /// <param name="builder">The configuration builder to extend.</param>
    /// <param name="landscape">The landscape; blank reads the <c>LANDSCAPE</c> variable.</param>
    /// <returns>The same builder.</returns>
    public static IConfigurationBuilder AddServiceConfiguration(
        this IConfigurationBuilder builder,
        string landscape)
    {
        ArgumentNullException.ThrowIfNull(builder);

        return builder.AddAtomiConfig(new AtomiConfigSource
        {
            BaseFile = BaseFile,
            LandscapePattern = LandscapePattern,
            Landscape = landscape,
            EnvPrefix = EnvironmentPrefix,
        });
    }

    /// <summary>
    /// Registers every configuration block this service composes. Engine blocks come from their
    /// own engine libraries and infra presets from standard-config; only the service-owned
    /// blocks are declared here.
    /// </summary>
    /// <param name="services">The service collection to extend.</param>
    /// <returns>The same collection.</returns>
    public static IServiceCollection AddServiceOptions(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        // The mandatory app: block.
        services.AddAtomiServiceTree();

        // Engine-owned blocks.
        services.RegisterOption<ErrorPortalOption>(ErrorPortalOption.Key);
        services.RegisterOption<OtelOption>(OtelOption.Key);

        // Infra presets, frozen family-wide by C0 §3.
        services.AddStandardConfigs(
            StandardConfigPreset.Postgres |
            StandardConfigPreset.Cache |
            StandardConfigPreset.Kv |
            StandardConfigPreset.Storage);

        // Service-owned blocks.
        services.RegisterOption<ServerOption, ServerOptionValidator>(ServerOption.Key);
        services.RegisterOption<AuthOption, AuthOptionValidator>(AuthOption.Key);
        services.RegisterOption<HttpOption, HttpOptionValidator>(HttpOption.Key);
        services.RegisterOption<DbInitOption, DbInitOptionValidator>(DbInitOption.Key);

        return services;
    }

    /// <summary>
    /// Builds the schema registry that <c>config:schema</c> generates from and CI verifies
    /// against. It must list exactly the blocks <see cref="AddServiceOptions"/> registers, or
    /// the generated schema describes a different service than the one that boots.
    /// </summary>
    /// <returns>A registry carrying every composed block.</returns>
    public static IConfigSchemaRegistry SchemaRegistry()
    {
        var registry = new ConfigSchemaRegistry();

        registry.Register<AppOption>(AppOption.Key);
        registry.Register<ErrorPortalOption>(ErrorPortalOption.Key);
        registry.Register<OtelOption>(OtelOption.Key);
        registry.Register<PostgresBlock>(PostgresOption.Key);
        registry.Register<CacheBlock>(CacheOption.Key);
        registry.Register<KvBlock>(KvOption.Key);
        registry.Register<StorageBlock>(StorageOption.Key);
        registry.Register<ServerOption>(ServerOption.Key);
        registry.Register<AuthOption>(AuthOption.Key);
        registry.Register<HttpOption>(HttpOption.Key);
        registry.Register<DbInitOption>(DbInitOption.Key);

        return registry;
    }

    /// <summary>
    /// Resolves a bound option block during composition, before the host is built.
    /// </summary>
    /// <typeparam name="T">The option type.</typeparam>
    /// <param name="services">The composed service collection.</param>
    /// <returns>The bound and validated value.</returns>
    public static T Resolve<T>(this IServiceCollection services)
        where T : class
    {
        ArgumentNullException.ThrowIfNull(services);
        using var provider = services.BuildServiceProvider();
        return provider.GetRequiredService<IOptions<T>>().Value;
    }
}
