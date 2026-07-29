namespace AtomiCloud.Diene.ApiEngine.Client;

/// <summary>
/// Resolves a registered typed client by its service-tree address.
/// </summary>
/// <remarks>
/// Every registration is also a keyed service, so a consumer can inject
/// <c>[FromKeyedServices("platform.service.module")]</c> directly and skip this seam. The tree
/// exists for call sites that hold an address as a value rather than as a compile-time
/// constant.
/// </remarks>
public interface IClientTree
{
    /// <summary>Gets the client registered for an address.</summary>
    /// <exception cref="InvalidOperationException">No client is registered for the address.</exception>
    TClient Get<TClient>(ServiceAddress address)
        where TClient : class;
}
