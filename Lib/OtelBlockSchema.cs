using System.Reflection;

namespace AtomiCloud.Diene.Otel;

/// <summary>
/// The engine-owned JSON Schema for the <c>otel:</c> block. The otel engine owns
/// the shape of its own block and ships it as a resource;
/// <c>AtomiCloud.Diene.Config</c> reads it to validate a service-composed root
/// without ever hard-coding these keys.
/// </summary>
public static class OtelBlockSchema
{
    /// <summary>The resource name the schema is embedded under.</summary>
    public const string ResourceName = "AtomiCloud.Diene.Otel.otel-block.schema.json";

    private static readonly Lazy<string> Lazy = new(Load);

    /// <summary>The schema document, as JSON text.</summary>
    public static string Json => Lazy.Value;

    private static string Load()
    {
        // The resource is embedded by Lib.csproj, so its presence is a build-time
        // invariant rather than a runtime condition. Asserting it with a null-check branch
        // would add a path no test can reach without breaking the build itself; a missing
        // resource instead surfaces as an ArgumentNullException from the reader.
        using var stream = typeof(OtelBlockSchema).GetTypeInfo().Assembly.GetManifestResourceStream(ResourceName)!;
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
