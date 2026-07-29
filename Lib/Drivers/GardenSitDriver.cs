using AtomiCloud.Diene.E2e.Garden;

namespace AtomiCloud.Diene.E2e.Drivers;

/// <summary>Drives a deployed Garden service through its final preview endpoint.</summary>
public sealed class GardenSitDriver : ISitDriver
{
    /// <summary>Initializes a driver for an absolute HTTP(S) endpoint.</summary>
    public GardenSitDriver(Uri endpoint, HttpMessageHandler? handler = null)
    {
        ArgumentNullException.ThrowIfNull(endpoint);
        if (!endpoint.IsAbsoluteUri || endpoint.Scheme is not ("http" or "https"))
        {
            throw new E2eHarnessException("Garden endpoint must be an absolute HTTP(S) URL");
        }

        this.Client = handler is null ? new HttpClient() : new HttpClient(handler);
        this.Client.BaseAddress = endpoint;
    }

    /// <inheritdoc />
    public HttpClient Client { get; }

    /// <inheritdoc />
    public ValueTask DisposeAsync()
    {
        this.Client.Dispose();
        return ValueTask.CompletedTask;
    }
}
