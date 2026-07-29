using Microsoft.AspNetCore.Mvc.Testing;

namespace AtomiCloud.Diene.E2e.Drivers;

/// <summary>Runs a service in-process while preserving its real ASP.NET request pipeline.</summary>
public sealed class InProcessSitDriver<TEntryPoint> : ISitDriver
    where TEntryPoint : class
{
    private readonly WebApplicationFactory<TEntryPoint> _factory;

    /// <summary>Starts from a default or caller-configured WebApplicationFactory.</summary>
    public InProcessSitDriver(WebApplicationFactory<TEntryPoint>? factory = null)
    {
        this._factory = factory ?? new WebApplicationFactory<TEntryPoint>();
        this.Client = this._factory.CreateClient();
    }

    /// <inheritdoc />
    public HttpClient Client { get; }

    /// <summary>Gets the service provider built by the application entry point.</summary>
    public IServiceProvider Services => this._factory.Services;

    /// <inheritdoc />
    public ValueTask DisposeAsync()
    {
        this.Client.Dispose();
        this._factory.Dispose();
        return ValueTask.CompletedTask;
    }
}
