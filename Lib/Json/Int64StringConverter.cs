using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.CoreUtils.Json;

/// <summary>
/// Carries a <see cref="long" /> as a decimal string. Wired in globally rather
/// than per-property: a value past the IEEE-754 safe range loses precision the
/// moment a JavaScript peer parses it as a JSON number, and which ids grow past
/// 2^53 is not knowable at design time.
/// </summary>
public sealed class Int64StringConverter : JsonConverter<long>
{
    /// <inheritdoc />
    public override long Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Number) return reader.GetInt64();
        if (reader.TokenType != JsonTokenType.String)
            throw new JsonException($"int64 must arrive as a JSON string, found {reader.TokenType}.");

        var decoded = Wire.ParseInt64(reader.GetString()!);
        if (decoded.IsSuccess(out var value)) return value;

        var error = decoded.GetFailure();
        throw new JsonException($"expected {error.Expected}, received \"{error.Actual}\".");
    }

    /// <inheritdoc />
    public override void Write(Utf8JsonWriter writer, long value, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(writer);
        writer.WriteStringValue(Wire.Format(value));
    }
}
