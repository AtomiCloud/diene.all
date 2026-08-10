using AtomiCloud.Diene.Config;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// Demo consumer of AtomiCloud.Diene.Config. Not packable — it exists to exercise the
/// shipped surface the way a real service does, and to own the schema generation task.
/// </summary>
public static class Program
{
    /// <summary>Runs the layering demo, or the schema task when asked.</summary>
    public static int Main(string[] args)
    {
        ArgumentNullException.ThrowIfNull(args);

        return args switch
        {
            ["schema", "write", var path] => Schema(ConfigSchemaGen.WriteSchema(ConfigComposition.Registry(), path)),
            ["schema", "verify", var path] => Schema(ConfigSchemaGen.VerifySchema(ConfigComposition.Registry(), path)),
            ["schema", ..] => Usage(),
            [] => Run(),
            _ => Usage(),
        };
    }

    private static int Run()
    {
        foreach (var line in Demo.Run()) Console.WriteLine(line);
        Console.WriteLine("Success: config layered, validated, and schema round-tripped");
        return 0;
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
        Console.Error.WriteLine("usage: App [schema write <path> | schema verify <path>]");
        return 2;
    }
}
