using AtomiCloud.Diene.Config;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// Demo consumer of AtomiCloud.Diene.StandardConfig. Not packable — it exists to exercise the
/// shipped surface the way a real service does, and to own the schema generation task.
/// </summary>
public static class Program
{
    /// <summary>Runs the preset demo, or the schema task when asked.</summary>
    public static async Task<int> Main(string[] args)
    {
        ArgumentNullException.ThrowIfNull(args);

        return args switch
        {
            ["schema", "write", var path] => Schema(ConfigSchemaGen.WriteSchema(ConfigComposition.Registry(), path)),
            ["schema", "verify", var path] => Schema(ConfigSchemaGen.VerifySchema(ConfigComposition.Registry(), path)),
            ["schema", ..] => Usage(),
            [] => Compose(),
            ["connect"] => await ConnectAsync().ConfigureAwait(false),
            _ => Usage(),
        };
    }

    /// <summary>
    /// The default run: compose and validate the presets WITHOUT touching a network, so the
    /// demo is runnable anywhere.
    /// </summary>
    private static int Compose()
    {
        foreach (var line in PresetDemo.Run()) Console.WriteLine(line);
        Console.WriteLine("Success: infra presets composed, validated, and schema round-tripped");
        return 0;
    }

    /// <summary>The dogfood run: the same blocks, with real dependencies behind them.</summary>
    private static async Task<int> ConnectAsync()
    {
        var landscape = Environment.GetEnvironmentVariable("LANDSCAPE") ?? "lapras";
        using var provider = ConfigComposition.Provider(ConfigComposition.Build(landscape));

        var result = await InfraDemo.RunAsync(provider).ConfigureAwait(false);

        return result.Match(
            lines =>
            {
                foreach (var line in lines) Console.WriteLine(line);
                Console.WriteLine("Success: every infra preset reached its dependency");
                return 0;
            },
            error =>
            {
                Console.Error.WriteLine($"❌ {error}");
                return 1;
            });
    }

    private static int Schema(Result<Unit, SchemaGenError> result) => result.Match(
        _ =>
        {
            Console.WriteLine("✅ Config schema is current");
            return 0;
        },
        error =>
        {
            Console.Error.WriteLine($"❌ {error.Fault} at {error.Path}: {error.Detail}");
            return 1;
        });

    private static int Usage()
    {
        Console.Error.WriteLine("usage: App [connect | schema write <path> | schema verify <path>]");
        return 2;
    }
}
