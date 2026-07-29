using AtomiCloud.Diene.ServerEngine.Module;
using AtomiCloud.DotnetBase.App.Webhooks;
using StackExchange.Redis;

namespace AtomiCloud.DotnetBase.App.StartUp.Registration;

/// <summary>Registers this service's inbound webhook handlers.</summary>
public static class WebhookRegistration
{
    /// <summary>
    /// Registers one handler per provider this service owns. The engine routes by
    /// <c>Provider</c>, and any provider without a handler answers 421 rather than 404.
    /// </summary>
    /// <param name="services">The service collection to extend.</param>
    /// <returns>The same collection.</returns>
    public static IServiceCollection AddServiceWebhookHandlers(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddAtomiWebhookHandler(provider =>
            new NoteWebhookHandler(provider.GetRequiredService<IConnectionMultiplexer>()));

        return services;
    }
}
