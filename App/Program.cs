using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;

namespace AtomiCloud.Diene.Problems.App;

/// <summary>Runs the full-API sample, serves one RFC 9457 response, and exits.</summary>
public static class Program
{
    /// <summary>Runs the demo consumer.</summary>
    public static async Task<int> Main(string[] args)
    {
        _ = args;
        var identity = new ProblemIdentity("raichu", "dotnet", "notes", "api");
        var portal = new ErrorPortalOption { Scheme = "https", Host = "docs.raichu.cluster.atomi.cloud" };
        Console.WriteLine(Samples.RunAll(identity, portal));

        await using var app = ProblemApp.Build(identity, portal);
        app.Urls.Add("http://127.0.0.1:0");
        await app.StartAsync().ConfigureAwait(false);
        var addresses = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>();
        var address = addresses?.Addresses.Single() ?? throw new InvalidOperationException("Kestrel did not publish an address.");
        using var client = new HttpClient { BaseAddress = new Uri(address) };
        using var response = await client.GetAsync("/notes/note-42").ConfigureAwait(false);
        Console.WriteLine(await response.Content.ReadAsStringAsync().ConfigureAwait(false));
        await app.StopAsync().ConfigureAwait(false);
        return response.StatusCode == System.Net.HttpStatusCode.NotFound ? 0 : 1;
    }
}
