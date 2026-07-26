using FluentValidation;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace AtomiCloud.Diene.Config;

/// <summary>
/// Binds an option block to a config key, validates it, and records it in the schema registry —
/// the one call a service makes per block it composes into its root config.
/// </summary>
public static class OptionRegistration
{
    /// <summary>
    /// Registers <typeparamref name="T" /> at <paramref name="key" /> with DataAnnotations
    /// validation. The trivial-block fallback: prefer the FluentValidation overload.
    /// </summary>
    public static OptionsBuilder<T> RegisterOption<T>(this IServiceCollection services, string key)
        where T : class
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentException.ThrowIfNullOrWhiteSpace(key);

        Registry(services).Register<T>(key);

        return services
            .AddOptions<T>()
            .BindConfiguration(ConfigKey.Path(key))
            .ValidateDataAnnotations()
            .ValidateOnStart();
    }

    /// <summary>
    /// Registers <typeparamref name="T" /> at <paramref name="key" /> validated by
    /// <typeparamref name="TValidator" /> — the family standard for option validation.
    /// </summary>
    public static OptionsBuilder<T> RegisterOption<T, TValidator>(this IServiceCollection services, string key)
        where T : class
        where TValidator : class, IValidator<T>
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentException.ThrowIfNullOrWhiteSpace(key);

        Registry(services).Register<T>(key);
        services.AddSingleton<IValidator<T>, TValidator>();
        services.AddSingleton<IValidateOptions<T>>(provider =>
            new FluentValidateOptions<T>(provider.GetRequiredService<IValidator<T>>(), key));

        return services
            .AddOptions<T>()
            .BindConfiguration(ConfigKey.Path(key))
            .ValidateOnStart();
    }

    /// <summary>
    /// The single registry instance for this service collection, created on first use.
    /// </summary>
    /// <remarks>
    /// Blocks are collected while services are being described, before any provider exists, so
    /// the instance is held by its own singleton descriptor rather than resolved from DI.
    /// </remarks>
    private static IConfigSchemaRegistry Registry(IServiceCollection services)
    {
        var existing = services
            .FirstOrDefault(descriptor => descriptor.ServiceType == typeof(IConfigSchemaRegistry));

        if (existing?.ImplementationInstance is IConfigSchemaRegistry registry) return registry;

        IConfigSchemaRegistry created = new ConfigSchemaRegistry();
        services.AddSingleton(created);
        return created;
    }
}
