using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.ServerEngine.Config;
using AtomiCloud.Diene.ServerEngine.Module;
using AtomiCloud.Diene.ServerEngine.TestHelper.Builders;
using AtomiCloud.Diene.ServerEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;

/// <summary>
/// An in-process host running this package's MVC surface with no real service behind it.
/// </summary>
/// <remarks>
/// <para>
/// It runs on <c>Microsoft.AspNetCore.TestHost</c>, so there is no socket, no port, and no
/// listener — but routing, model binding, the filter pipeline, and content negotiation are the
/// real ones. That distinction matters for a server library: the status code a filter produces,
/// the media type it writes, and whether a route was discovered at all only exist once a request
/// has crossed the pipeline, and none of them can be proven by calling a controller method.
/// </para>
/// <para>
/// The clock and the secrets are fakes the caller can reach afterwards, because the two hardest
/// webhook cases to test against real ones are a stale timestamp and a key rotation.
/// </para>
/// </remarks>
public sealed class ServerEngineTestHost : IAsyncDisposable
{
    private readonly IHost _host;

    private ServerEngineTestHost(
        IHost host,
        HttpClient client,
        FakeAuthClock clock,
        FakeWebhookSecretProvider secrets)
    {
        this._host = host;
        this.Client = client;
        this.Clock = clock;
        this.Secrets = secrets;
    }

    /// <summary>Gets a client whose requests enter the pipeline directly.</summary>
    public HttpClient Client { get; }

    /// <summary>Gets the clock the host reads, so a test can advance it past the signature window.</summary>
    public FakeAuthClock Clock { get; }

    /// <summary>Gets the receiver's key set, so a test can rotate or forget the secret.</summary>
    public FakeWebhookSecretProvider Secrets { get; }

    /// <summary>Gets the host's services, for resolving a registered handler or the registry.</summary>
    public IServiceProvider Services => this._host.Services;

    /// <summary>Starts a host, optionally configured.</summary>
    public static async Task<ServerEngineTestHost> StartAsync(Action<ServerEngineTestHostOptions>? configure = null)
    {
        var options = new ServerEngineTestHostOptions();
        configure?.Invoke(options);

        var config = BuildConfig(options.Tolerance);
        var clock = new FakeAuthClock(options.Now);
        var secrets = new FakeWebhookSecretProvider([.. options.SigningKeys]);

        var host = await new HostBuilder()
            .ConfigureWebHost(web => web
                .UseTestServer()
                .ConfigureServices(services => Register(services, options, config, clock, secrets))
                .Configure(app => app.UseRouting().UseEndpoints(endpoints => endpoints.MapControllers())))
            .ConfigureLogging(logging => logging.ClearProviders())
            .StartAsync()
            .ConfigureAwait(false);

        return new ServerEngineTestHost(host, host.GetTestClient(), clock, secrets);
    }

    /// <summary>Posts a signed delivery for a provider and returns the raw response.</summary>
    public Task<HttpResponseMessage> DeliverAsync(
        string provider,
        byte[] body,
        DateTimeOffset? signedAt = null,
        string key = WebhookRequestSigner.DefaultKey,
        string mediaType = WebhookProtocol.MediaType,
        string? header = null,
        CancellationToken cancellationToken = default) =>
        this.Client.SendAsync(
            WebhookRequestSigner.Request(
                provider,
                body,
                signedAt ?? this.Clock.UtcNow,
                key,
                mediaType,
                header),
            cancellationToken);

    /// <inheritdoc />
    public async ValueTask DisposeAsync()
    {
        this.Client.Dispose();
        await this._host.StopAsync().ConfigureAwait(false);
        this._host.Dispose();
    }

    private static void Register(
        IServiceCollection services,
        ServerEngineTestHostOptions options,
        ServerEngineConfig config,
        FakeAuthClock clock,
        FakeWebhookSecretProvider secrets)
    {
        services.AddAtomiProblems(
            new ProblemIdentity(
                config.Identity.Landscape,
                config.Identity.Platform,
                config.Identity.Service,
                config.Identity.Module),
            new ErrorPortalOption { Scheme = "https", Host = "errors.test.invalid" },
            catalog =>
            {
                if (options.IncludeBaselineProblems) catalog.AddBaseline();
            });

        services.TryAddSingleton<IAuthClock>(clock);
        services.TryAddSingleton<IWebhookSecretProvider>(secrets);
        services.AddAtomiServerEngine(config);

        foreach (var handler in options.Handlers) services.AddSingleton<IWebhookHandler>(handler);

        // The probe controller lives in THIS assembly, which the engine's own application part
        // does not cover, so it is added explicitly.
        services.AddControllers().AddApplicationPart(typeof(ProbeController).Assembly);

        options.Services?.Invoke(services);
    }

    private static ServerEngineConfig BuildConfig(TimeSpan tolerance)
    {
        var identity = ServiceIdentityConfig
            .Create("lapras", "sulfoxide", "probe", "api", "0.0.0-test")
            .Get();
        return ServerEngineConfig.Create(identity, WebhookConfig.Create(tolerance).Get()).Get();
    }
}
