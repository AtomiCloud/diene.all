using System.Text.Json;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.ServerEngine.Config;
using AtomiCloud.Diene.ServerEngine.Mvc;
using AtomiCloud.Diene.ServerEngine.Onboarding;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace AtomiCloud.Diene.ServerEngine.Module;

/// <summary>
/// Registers the server engine as an enable-able module: nothing is hosted implicitly.
/// </summary>
public static class ServerEngineServiceCollectionExtensions
{
    /// <summary>
    /// The controllers this package mounts, in route order. Exposed so a host can log what it
    /// just enabled and a test can assert the routes were actually discovered — the one failure
    /// mode of application-part registration is silent, and this is what makes it assertable.
    /// </summary>
    public static IReadOnlyList<Type> ShippedControllers { get; } =
    [
        typeof(SystemController),
        typeof(WebhookController),
        typeof(OnboardSyncController),
    ];

    /// <summary>
    /// Registers the configuration, the exception-to-Problem filter, the shipped controllers,
    /// and the C0-conformant JSON contract for the MVC surface.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The shipped controllers live in this assembly, so it is added as an MVC application part
    /// explicitly. Without that, controller discovery only scans the entry assembly and the
    /// system, webhook, and OnboardSync routes would be absent with no error anywhere — the
    /// service would simply 404 endpoints it believes it exposes.
    /// </para>
    /// <para>
    /// The wire converters are applied to MVC's own JSON options rather than only used inside
    /// this package, because the point of the contract is that EVERY payload a Diene service
    /// emits obeys it — not just the ones this package happens to write.
    /// </para>
    /// </remarks>
    public static IServiceCollection AddAtomiServerEngine(
        this IServiceCollection services,
        ServerEngineConfig config)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(config);

        services.AddSingleton(config);
        services.AddSingleton(config.Identity);
        services.AddSingleton(config.Webhooks);

        services.TryAddSingleton<IWebhookSignatureVerifier, HmacWebhookSignatureVerifier>();
        services.TryAddSingleton<WebhookHandlerRegistry>();

        services.AddControllers(options => options.Filters.Add<DomainProblemExceptionFilter>())
            .AddApplicationPart(typeof(ServerEngineServiceCollectionExtensions).Assembly)
            .AddJsonOptions(options => ApplyWireContract(options.JsonSerializerOptions));

        return services;
    }

    /// <summary>
    /// Registers a webhook handler for one provider. Call it once per provider a service
    /// subscribes to.
    /// </summary>
    public static IServiceCollection AddAtomiWebhookHandler<THandler>(this IServiceCollection services)
        where THandler : class, IWebhookHandler
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddSingleton<IWebhookHandler, THandler>();
        return services;
    }

    /// <summary>
    /// Registers the per-platform internal webhook secrets. Supply every currently live
    /// rotation key, because C0 requires a delivery to verify against any of them.
    /// </summary>
    public static IServiceCollection AddAtomiWebhookSecrets(
        this IServiceCollection services,
        params string[] keys)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IWebhookSecretProvider>(new StaticWebhookSecretProvider(keys));
        return services;
    }

    /// <summary>
    /// Applies the C0 §1 wire contract plus snake_case enum names to serializer options a host
    /// already owns.
    /// </summary>
    public static void ApplyWireContract(JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        options.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        options.DictionaryKeyPolicy = JsonNamingPolicy.CamelCase;
        options.NumberHandling = JsonNumberHandling.Strict;
        options.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
        AtomiJson.Apply(options);

        // Enums cross the wire as snake_case names, never as ordinals. An ordinal is a
        // renumbering away from silently meaning something else to a consumer that has not
        // been redeployed, and the name is the part the contract actually fixes.
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower));
    }
}
