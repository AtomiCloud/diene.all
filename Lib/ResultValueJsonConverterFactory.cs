using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Results;

/// <summary>Rejects accidental serialization of in-memory Result values.</summary>
public sealed class ResultValueJsonConverterFactory : JsonConverterFactory
{
    /// <inheritdoc />
    public override bool CanConvert(Type typeToConvert) =>
        typeToConvert.IsGenericType && typeToConvert.GetGenericTypeDefinition() == typeof(Result<,>);

    /// <inheritdoc />
    public override JsonConverter CreateConverter(Type typeToConvert, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(typeToConvert);
        ArgumentNullException.ThrowIfNull(options);
        return (JsonConverter)Activator.CreateInstance(
            typeof(ResultValueJsonConverter<,>).MakeGenericType(typeToConvert.GetGenericArguments()))!;
    }

    private sealed class ResultValueJsonConverter<T, E> : JsonConverter<Result<T, E>>
    {
        public override Result<T, E> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            throw new NotSupportedException("Deserialize ResultSerial<T, E> and call Result.FromSerial instead.");

        public override void Write(Utf8JsonWriter writer, Result<T, E> value, JsonSerializerOptions options) =>
            throw new NotSupportedException("Call Result.ToSerial before serializing a Result.");
    }
}
