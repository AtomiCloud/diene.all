using AtomiCloud.Diene.ApiEngine.Calls;
using AtomiCloud.Diene.ApiEngine.Client;
using AtomiCloud.Diene.ApiEngine.Config;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.Diene.ApiEngine.Module;

/// <summary>
/// Registers the client tree as an enable-able module. A consumer opts in by calling
/// <see cref="AddAtomiClientTree" />; nothing is registered implicitly.
/// </summary>
public static class ApiEngineServiceCollectionExtensions
{
    /// <summary>
    /// Registers the validated upstream configuration, the caller, the tree, and every backend
    /// the build callback declares.
    /// </summary>
    /// <remarks>
    /// The configuration is taken already-validated rather than bound here: the config library
    /// is the sole merger and validator of a service's root, and a second binder in an engine
    /// would be a second place for the same value to be interpreted differently.
    /// </remarks>
    public static IServiceCollection AddAtomiClientTree(
        this IServiceCollection services,
        ApiEngineConfig config,
        Action<ClientTreeBuilder> build)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(config);
        ArgumentNullException.ThrowIfNull(build);

        services.AddSingleton(config);
        services.AddSingleton<IClientTree, ClientTree>();
        services.AddSingleton<IApiCaller, ApiCaller>();

        build(new ClientTreeBuilder(services, config));
        return services;
    }
}
