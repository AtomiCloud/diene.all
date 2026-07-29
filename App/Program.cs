using AtomiCloud.Diene.E2e;
using AtomiCloud.Diene.E2e.Demo;
using AtomiCloud.Diene.E2e.Drivers;
using AtomiCloud.Diene.E2e.Garden;

if (args.Contains("--exercise-e2e-harness", StringComparer.Ordinal))
{
    ExerciseHarness();
    return;
}

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var endpoints = app.MapDemoEndpoint();
endpoints.MapGet("/system/packages", () => new
{
    Runtime = PublishedPackageBundle.RuntimeAssemblyNames.Count,
    TestHelpers = PublishedPackageBundle.TestHelperAssemblyNames.Count,
});
app.Run();

static void ExerciseHarness()
{
    _ = new Program();

    var fixture = new GardenNamespaceFixture(
        "api",
        "service",
        "platform",
        "preview",
        "dev",
        "example");
    var endpoint = GardenPreviewEndpoint.Resolve(fixture.Hostname, fixture);
    ISitDriver garden = new GardenSitDriver(endpoint);
    try
    {
        _ = garden.Client;
        _ = SitDriverSelection.Resolve("inprocess");

        var inProcess = new InProcessSitDriver<Program>();
        try
        {
            _ = inProcess.Client;
            _ = inProcess.Services;

            Console.WriteLine(
                $"{endpoint} carries {PublishedPackageBundle.RuntimeAssemblyNames.Count} runtime " +
                $"and {PublishedPackageBundle.TestHelperAssemblyNames.Count} TestHelper packages.");
        }
        finally
        {
            inProcess.DisposeAsync().GetAwaiter().GetResult();
        }
    }
    finally
    {
        garden.DisposeAsync().GetAwaiter().GetResult();
    }
}

/// <summary>Public entry point used by WebApplicationFactory consumers.</summary>
public partial class Program;
