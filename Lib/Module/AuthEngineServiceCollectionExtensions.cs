using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.Tokens;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.Diene.AuthEngine.Module;

/// <summary>
/// Registers the auth engine as an enable-able module. A consumer opts in by calling
/// <see cref="AddAtomiAuthEngine" />; nothing is hosted implicitly.
/// </summary>
public static class AuthEngineServiceCollectionExtensions
{
    /// <summary>
    /// Registers configuration, the clock, key resolution, token validation, the guard,
    /// and the client-side credential surface.
    /// </summary>
    /// <remarks>
    /// The clock and key resolver are registered with <c>TryAdd</c> so a consumer that has
    /// already supplied its own — a fixed clock in a test host, a pre-seeded key set —
    /// keeps it. Registering unconditionally would silently override the substitution a
    /// test just made, which is the kind of override that surfaces as an unexplained
    /// failure far from its cause.
    /// </remarks>
    public static IServiceCollection AddAtomiAuthEngine(
        this IServiceCollection services,
        AuthEngineConfig config)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(config);

        services.AddSingleton(config);
        services.AddSingleton(config.Lifetimes);

        Microsoft.Extensions.DependencyInjection.Extensions.ServiceCollectionDescriptorExtensions
            .TryAddSingleton<IAuthClock>(services, SystemAuthClock.Instance);

        services.AddHttpClient<ISigningKeyResolver, OpenIdSigningKeyResolver>();
        services.AddHttpClient<ICredentialClient, LogtoCredentialClient>();

        services.AddSingleton<ITokenValidator, JwtTokenValidator>();
        services.AddSingleton<AuthGuard>();
        services.AddSingleton<TokenCache>();

        return services;
    }
}
