namespace AtomiCloud.Diene.E2e.Drivers;

/// <summary>A black-box HTTP entry into a service under test.</summary>
public interface ISitDriver : IAsyncDisposable
{
    /// <summary>Gets the client whose requests enter the service boundary.</summary>
    HttpClient Client { get; }
}
