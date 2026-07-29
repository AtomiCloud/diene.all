using AtomiCloud.Diene.ApiEngine.Config;
using AtomiCloud.Diene.ApiEngine.Transport;
using AtomiCloud.Diene.AuthEngine.Client;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.Diene.ApiEngine.Client;

/// <summary>
/// The one place a consumer declares a backend. Each registration produces a named
/// <c>HttpClient</c> carrying this engine's pipeline, plus a keyed typed client built over it.
/// </summary>
/// <remarks>
/// The generated SDK is supplied as a factory over an <c>HttpClient</c> rather than
/// constructed here, which is what keeps the engine generator-agnostic: any client that can be
/// built over an <c>HttpClient</c> — Kiota-generated or otherwise — registers the same way.
/// </remarks>
public sealed class ClientTreeBuilder
{
    private readonly IServiceCollection _services;
    private readonly ApiEngineConfig _config;
    private readonly List<ServiceAddress> _registered = [];

    internal ClientTreeBuilder(IServiceCollection services, ApiEngineConfig config)
    {
        _services = services;
        _config = config;
    }

    /// <summary>Gets the addresses registered so far, in registration order.</summary>
    public IReadOnlyList<ServiceAddress> Registered => _registered;

    /// <summary>
    /// Registers one backend: its base address and timeout come from configuration, its auth
    /// binding from that same entry, and its typed client from the supplied factory.
    /// </summary>
    /// <exception cref="InvalidOperationException">
    /// The address has no configuration entry, or is registered twice.
    /// </exception>
    public ClientTreeBuilder Register<TClient>(ServiceAddress address, Func<HttpClient, TClient> sdkFactory)
        where TClient : class
    {
        ArgumentNullException.ThrowIfNull(address);
        ArgumentNullException.ThrowIfNull(sdkFactory);

        var key = address.ToString();

        // An unconfigured backend fails here rather than at the first call to it. The
        // alternative — defaulting a base address — is how a service ends up quietly calling
        // localhost in production.
        if (!_config.Find(address).IsSome(out var upstream))
        {
            throw new InvalidOperationException(
                $"Upstream '{key}' has no '{HttpClientOption.Key}' configuration entry.");
        }

        if (_registered.Any(existing => existing.ToString() == key))
        {
            throw new InvalidOperationException($"Upstream '{key}' is already registered.");
        }

        var builder = _services
            .AddHttpClient(key, client =>
            {
                client.BaseAddress = upstream.BaseAddress;
                client.Timeout = upstream.Timeout;
            });

        // Ordering is load-bearing and reads outermost-first. Auth runs first so one token is
        // attached and reused across the retry; the capture runs innermost so it observes the
        // exchange that actually happened, and counts every attempt including the retried one.
        if (upstream.AuthResource is not null)
        {
            builder.AddHttpMessageHandler(services => new AtomiAuthHandler(
                services.GetRequiredService<TokenCache>(),
                upstream.AuthResource,
                upstream.AuthScopes));
        }

        builder.AddHttpMessageHandler(() => new RetryOnceHandler());
        builder.AddHttpMessageHandler(() => new FailureCaptureHandler());

        _services.AddKeyedTransient(key, (services, _) =>
            sdkFactory(services.GetRequiredService<IHttpClientFactory>().CreateClient(key)));

        _registered.Add(address);
        return this;
    }
}
