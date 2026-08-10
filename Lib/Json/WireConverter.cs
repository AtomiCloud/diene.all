using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.CoreUtils.Json;

/// <summary>
/// Shared plumbing for the wire converters: read a JSON string, hand it to the
/// matching <see cref="Wire" /> codec, and surface a rejection as the
/// <see cref="JsonException" /> System.Text.Json expects.
/// </summary>
/// <typeparam name="T">The domain type carried by the wire form.</typeparam>
public abstract class WireConverter<T> : JsonConverter<T>
{
    /// <summary>Decodes the wire form into its domain value.</summary>
    protected abstract Result<T, WireFormatError> Parse(string wire);

    /// <summary>Encodes a domain value into its canonical wire form.</summary>
    protected abstract string Format(T value);

    /// <inheritdoc />
    public sealed override T Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.String)
            throw new JsonException($"{typeof(T).Name} must arrive as a JSON string, found {reader.TokenType}.");

        var decoded = Parse(reader.GetString()!);
        if (decoded.IsSuccess(out var value)) return value;

        var error = decoded.GetFailure();
        throw new JsonException($"expected {error.Expected}, received \"{error.Actual}\".");
    }

    /// <inheritdoc />
    public sealed override void Write(Utf8JsonWriter writer, T value, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(writer);
        writer.WriteStringValue(Format(value));
    }
}
