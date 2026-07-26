using AtomiCloud.Diene.Config;
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.Diene.StandardConfig.Presets;

/// <summary>The infra presets this library ships, by their C0-frozen block key.</summary>
[Flags]
public enum StandardConfigPreset
{
    /// <summary>No preset.</summary>
    None = 0,

    /// <summary>The <c>postgres</c> block.</summary>
    Postgres = 1,

    /// <summary>The <c>cache</c> block (RAM-backed, ephemeral).</summary>
    Cache = 2,

    /// <summary>The <c>kv</c> block (persistent).</summary>
    Kv = 4,

    /// <summary>The <c>storage</c> block (S3-compatible).</summary>
    Storage = 8,

    /// <summary>Every preset this library ships.</summary>
    All = Postgres | Cache | Kv | Storage,
}

/// <summary>
/// Registers the chosen infra presets into a service's composed root config.
/// </summary>
/// <remarks>
/// This library ships SCHEMAS, never a loader: it neither reads YAML nor merges layers nor
/// validates a root document. Each call below hands one option block to the config lib — the
/// sole merger and validator — which binds it, validates it at <c>ValidateOnStart</c>, and
/// records it in the schema registry backing the generated <c>$schema</c> pointer. A service
/// composes its root schema as one line per engine block, plus the presets it needs from here,
/// plus its own keys.
/// </remarks>
public static class StandardConfigRegistration
{
    /// <summary>Registers every preset named in <paramref name="presets" />.</summary>
    /// <example>
    /// <code>
    /// services.AddStandardConfigs(StandardConfigPreset.Postgres | StandardConfigPreset.Cache);
    /// </code>
    /// </example>
    public static IServiceCollection AddStandardConfigs(
        this IServiceCollection services,
        StandardConfigPreset presets)
    {
        ArgumentNullException.ThrowIfNull(services);

        if (presets.HasFlag(StandardConfigPreset.Postgres)) services.AddPostgresPreset();
        if (presets.HasFlag(StandardConfigPreset.Cache)) services.AddCachePreset();
        if (presets.HasFlag(StandardConfigPreset.Kv)) services.AddKvPreset();
        if (presets.HasFlag(StandardConfigPreset.Storage)) services.AddStoragePreset();

        return services;
    }

    /// <summary>Registers the keyed <c>postgres</c> block as <c>IOptions&lt;PostgresBlock&gt;</c>.</summary>
    public static IServiceCollection AddPostgresPreset(this IServiceCollection services) =>
        Register<PostgresBlock, PostgresBlockValidator>(services, PostgresOption.Key);

    /// <summary>Registers the keyed <c>cache</c> block as <c>IOptions&lt;CacheBlock&gt;</c>.</summary>
    public static IServiceCollection AddCachePreset(this IServiceCollection services) =>
        Register<CacheBlock, CacheBlockValidator>(services, CacheOption.Key);

    /// <summary>Registers the keyed <c>kv</c> block as <c>IOptions&lt;KvBlock&gt;</c>.</summary>
    public static IServiceCollection AddKvPreset(this IServiceCollection services) =>
        Register<KvBlock, KvBlockValidator>(services, KvOption.Key);

    /// <summary>Registers the keyed <c>storage</c> block as <c>IOptions&lt;StorageBlock&gt;</c>.</summary>
    public static IServiceCollection AddStoragePreset(this IServiceCollection services) =>
        Register<StorageBlock, StorageBlockValidator>(services, StorageOption.Key);

    /// <summary>
    /// Every preset registers the SAME way — as a keyed block, never a bare entry — which is
    /// what makes a second named instance pure YAML.
    /// </summary>
    private static IServiceCollection Register<TBlock, TValidator>(IServiceCollection services, string key)
        where TBlock : class
        where TValidator : class, IValidator<TBlock>
    {
        ArgumentNullException.ThrowIfNull(services);
        return services.RegisterOption<TBlock, TValidator>(key).Services;
    }
}
