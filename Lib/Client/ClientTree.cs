using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.Diene.ApiEngine.Client;

/// <summary>Resolves keyed client registrations out of the container.</summary>
/// <param name="services">The container the clients were registered in.</param>
public sealed class ClientTree(IServiceProvider services) : IClientTree
{
    private readonly IServiceProvider _services = services ?? throw new ArgumentNullException(nameof(services));

    /// <inheritdoc />
    /// <remarks>
    /// An unregistered address throws rather than returning null. A missing backend is a
    /// composition defect, and a null client would surface it as a null-reference far away
    /// from the registration that was never written.
    /// </remarks>
    public TClient Get<TClient>(ServiceAddress address)
        where TClient : class
    {
        ArgumentNullException.ThrowIfNull(address);
        var key = address.ToString();
        return _services.GetKeyedService<TClient>(key)
               ?? throw new InvalidOperationException(
                   $"No {typeof(TClient).Name} client is registered for upstream '{key}'.");
    }
}
