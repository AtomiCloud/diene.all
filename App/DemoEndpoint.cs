namespace AtomiCloud.Diene.E2e.Demo;

/// <summary>The smallest service consumer that proves the in-process SIT driver.</summary>
public static class DemoEndpoint
{
    /// <summary>Maps the demo health route.</summary>
    public static IEndpointRouteBuilder MapDemoEndpoint(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);
        endpoints.MapGet("/system/health", () => new { Status = "ok" });
        return endpoints;
    }
}
