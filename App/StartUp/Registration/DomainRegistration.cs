using AtomiCloud.Diene.StandardConfig.Presets;
using AtomiCloud.DotnetBase.App.Adapters.Postgres;
using AtomiCloud.DotnetBase.App.Adapters.Redis;
using AtomiCloud.DotnetBase.Lib.Note;
using Microsoft.Extensions.Options;
using StackExchange.Redis;

namespace AtomiCloud.DotnetBase.App.StartUp.Registration;

/// <summary>Cache, domain, and job layers of the composition root.</summary>
public static class DomainRegistration
{
    /// <summary>The connection name every preset in this service reads.</summary>
    public const string PrimaryConnection = "MAIN";

    /// <summary>
    /// Registers the ephemeral cache connection. This is the <c>cache:</c> preset, not
    /// <c>kv:</c> — they speak the same protocol and differ on the only thing that matters,
    /// which is whether losing the data is acceptable.
    /// </summary>
    /// <param name="services">The service collection to extend.</param>
    /// <returns>The same collection.</returns>
    public static IServiceCollection AddServiceCache(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddSingleton<IConnectionMultiplexer>(provider =>
        {
            var cache = provider.GetRequiredService<IOptions<CacheBlock>>().Value.Named(PrimaryConnection);
            return ConnectionMultiplexer.Connect(RedisConfiguration(cache));
        });

        return services;
    }

    /// <summary>Registers the fenced sample domain. Swapping the sample replaces this method.</summary>
    /// <param name="services">The service collection to extend.</param>
    /// <returns>The same collection.</returns>
    public static IServiceCollection AddServiceDomain(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        // ── Domain wiring (illustrative sample) — replace this block with your domain ──
        services.AddSingleton<INoteSummariser, NoteSummariser>();
        services.AddScoped<PostgresNoteRepository>();
        services.AddScoped<INoteRepository>(provider => provider.GetRequiredService<PostgresNoteRepository>());
        services.AddScoped<INoteCatalogue>(provider => provider.GetRequiredService<PostgresNoteRepository>());
        services.AddScoped<INotes, Notes>();
        services.AddScoped<RedisNoteRepository>();
        // ── End domain wiring ──

        return services;
    }

    /// <summary>
    /// Registers background work. The one-shot initialisation path is deliberately NOT a hosted
    /// service: it runs as its own hook-scoped Job before the rollout, so that a migration can
    /// never be a reason the serving deployment recreates.
    /// </summary>
    /// <param name="services">The service collection to extend.</param>
    /// <returns>The same collection.</returns>
    public static IServiceCollection AddServiceJobs(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);
        return services;
    }

    /// <summary>Builds a StackExchange.Redis configuration from a preset connection entry.</summary>
    /// <param name="option">The bound, named connection.</param>
    /// <returns>Configuration ready to connect with.</returns>
    public static ConfigurationOptions RedisConfiguration(RedisConnectionOption option)
    {
        ArgumentNullException.ThrowIfNull(option);

        var configuration = new ConfigurationOptions
        {
            DefaultDatabase = option.Db,
            Ssl = option.Tls,
            AbortOnConnectFail = false,
        };

        configuration.EndPoints.Add(option.Host, option.Port);
        if (!string.IsNullOrEmpty(option.Password)) configuration.Password = option.Password;

        return configuration;
    }
}
