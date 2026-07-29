using AtomiCloud.Diene.ApiEngine.Client;

namespace AtomiCloud.Diene.ApiEngine.TestHelper.Fakes;

/// <summary>
/// An in-memory <see cref="IClientTree" /> for testing code that resolves clients from the tree
/// without standing up a container.
/// </summary>
/// <remarks>
/// This is for the consumer whose subject takes <c>IClientTree</c> and calls
/// <c>Get&lt;TClient&gt;</c>. A consumer testing the pipeline itself should register a real tree
/// against a <see cref="FakeUpstream" /> instead — this double deliberately has no pipeline, so
/// it cannot prove anything about auth attachment, retries, or classification.
/// </remarks>
public sealed class FakeClientTree : IClientTree
{
    private readonly Dictionary<string, object> _clients = new(StringComparer.Ordinal);

    /// <summary>Gets the addresses resolved through this tree, in call order.</summary>
    public IReadOnlyList<ServiceAddress> Resolved => _resolved;

    private readonly List<ServiceAddress> _resolved = [];

    /// <summary>Registers a client for an address.</summary>
    public void Register<TClient>(ServiceAddress address, TClient client)
        where TClient : class
    {
        ArgumentNullException.ThrowIfNull(address);
        ArgumentNullException.ThrowIfNull(client);
        _clients[address.ToString()] = client;
    }

    /// <inheritdoc />
    public TClient Get<TClient>(ServiceAddress address)
        where TClient : class
    {
        ArgumentNullException.ThrowIfNull(address);
        _resolved.Add(address);

        var key = address.ToString();
        if (!_clients.TryGetValue(key, out var client))
        {
            throw new InvalidOperationException($"No client is registered for upstream '{key}'.");
        }

        // Mirrors the real tree: a wrong requested type is a composition defect, and reporting it
        // as "not registered" would send the reader looking for a missing Register call that is
        // actually there.
        return client as TClient
               ?? throw new InvalidOperationException(
                   $"Upstream '{key}' is registered as {client.GetType().Name}, not {typeof(TClient).Name}.");
    }
}
