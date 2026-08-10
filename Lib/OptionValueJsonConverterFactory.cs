using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Results;

/// <summary>Rejects accidental serialization of in-memory Option values.</summary>
public sealed class OptionValueJsonConverterFactory : JsonConverterFactory
{
    /// <inheritdoc />
    public override bool CanConvert(Type typeToConvert) =>
        typeToConvert.IsGenericType && typeToConvert.GetGenericTypeDefinition() == typeof(Option<>);

    /// <inheritdoc />
    public override JsonConverter CreateConverter(Type typeToConvert, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(typeToConvert);
        ArgumentNullException.ThrowIfNull(options);
        return (JsonConverter)Activator.CreateInstance(
            typeof(OptionValueJsonConverter<>).MakeGenericType(typeToConvert.GetGenericArguments()))!;
    }

    private sealed class OptionValueJsonConverter<T> : JsonConverter<Option<T>>
    {
        public override Option<T> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            throw new NotSupportedException("Deserialize OptionSerial<T> and call Option.FromSerial instead.");

        public override void Write(Utf8JsonWriter writer, Option<T> value, JsonSerializerOptions options) =>
            throw new NotSupportedException("Call Option.ToSerial before serializing an Option.");
    }
}
