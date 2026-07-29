namespace AtomiCloud.Diene.E2e.Drivers;

/// <summary>The service venue selected by SIT_DRIVER.</summary>
public enum SitDriverKind
{
    /// <summary>Run the service in-process through WebApplicationFactory.</summary>
    InProcess,

    /// <summary>Drive a deployed Garden preview endpoint over HTTP.</summary>
    Garden,
}
