using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.CoreUtils.Json;

/// <summary>
/// The System.Text.Json entry point for the C0 §1 wire contract. Register these
/// options once at composition and every date, time, instant, duration,
/// timezone, decimal, and 64-bit integer in the payload obeys the contract
/// without a single per-property attribute.
/// </summary>
public static class AtomiJson
{
    private static readonly JsonSerializerOptions Defaults = Build();

    /// <summary>Serializer options carrying the whole wire contract.</summary>
    public static JsonSerializerOptions DefaultOptions => Defaults;

    /// <summary>
    /// Adds the wire converters to serializer options a caller already owns, for
    /// hosts that configure <c>JsonOptions</c> themselves.
    /// </summary>
    public static void Apply(JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        options.Converters.Add(new WireDateConverter());
        options.Converters.Add(new WireTimeConverter());
        options.Converters.Add(new WireInstantConverter());
        options.Converters.Add(new WireDurationConverter());
        options.Converters.Add(new WireTimeZoneConverter());
        options.Converters.Add(new DecimalStringConverter());
        options.Converters.Add(new Int64StringConverter());
    }

    private static JsonSerializerOptions Build()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DictionaryKeyPolicy = JsonNamingPolicy.CamelCase,
            NumberHandling = JsonNumberHandling.Strict,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        };
        Apply(options);

        // Locked at construction so a caller cannot bolt a converter onto the
        // shared instance and change how every other caller serializes.
        options.MakeReadOnly(populateMissingResolver: true);
        return options;
    }
}
