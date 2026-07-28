using AtomiCloud.Diene.ApiEngine.Client;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// Composition root and demo consumer: registers two upstreams and walks every branch of the
/// classification matrix against a real HTTP server.
/// </summary>
public static class Program
{
    /// <summary>Runs the demo and returns a process exit code.</summary>
    public static async Task<int> Main(string[] args)
    {
        _ = args;

        await using var upstream = await DemoUpstream.StartAsync().ConfigureAwait(false);
        Console.WriteLine($"demo upstream listening on {upstream.BaseAddress}");

        var built = ApiEngineDemo.BuildConfig(upstream.BaseAddress);
        if (built.IsFailure(out var error))
        {
            Console.WriteLine($"configuration rejected -> {error}");
            return 1;
        }

        var config = built.Get();
        Console.WriteLine(
            $"registered {config.Upstreams.Count} upstream(s), " +
            $"timeout {config.Find(ApiEngineDemo.Notes).Get().Timeout}");

        await using var services = ApiEngineDemo.Compose(config);
        Console.WriteLine($"client tree resolved: {services.GetRequiredService<IClientTree>().GetType().Name}");

        // One line per classification branch. The success case first, so a failure in the
        // interesting cases cannot be mistaken for the whole pipeline being broken.
        Console.WriteLine(await ApiEngineDemo
            .Describe(services, ApiEngineDemo.Notes, DemoUpstream.OkPath).ConfigureAwait(false));
        Console.WriteLine(await ApiEngineDemo
            .DescribePing(services, ApiEngineDemo.Notes, DemoUpstream.OkPath).ConfigureAwait(false));
        Console.WriteLine(await ApiEngineDemo
            .Describe(services, ApiEngineDemo.Notes, DemoUpstream.ProblemPath).ConfigureAwait(false));
        Console.WriteLine(await ApiEngineDemo
            .Describe(services, ApiEngineDemo.Notes, DemoUpstream.NestedProblemPath).ConfigureAwait(false));
        Console.WriteLine(await ApiEngineDemo
            .Describe(services, ApiEngineDemo.Notes, DemoUpstream.LegacyPath).ConfigureAwait(false));
        Console.WriteLine(await ApiEngineDemo
            .Describe(services, ApiEngineDemo.Notes, DemoUpstream.GarbagePath).ConfigureAwait(false));
        Console.WriteLine(await ApiEngineDemo
            .Describe(services, ApiEngineDemo.Notes, DemoUpstream.SilentPath).ConfigureAwait(false));

        // The second upstream shares the first one's host, so the tokens the server saw are the
        // evidence that each backend carried its own credential.
        Console.WriteLine(await ApiEngineDemo
            .Describe(services, ApiEngineDemo.Archive, DemoUpstream.OkPath).ConfigureAwait(false));
        Console.WriteLine(
            $"tokens seen upstream: {string.Join(", ", upstream.Authorizations.Distinct().Order())}");

        Console.WriteLine(await ApiEngineDemo.DescribeUnreachable(services).ConfigureAwait(false));
        Console.WriteLine(ApiEngineDemo.DescribeCatalog());
        return 0;
    }
}
