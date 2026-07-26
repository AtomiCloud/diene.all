using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.CoreUtils.Json;

/// <summary>
/// Carries a <see cref="decimal" /> as a decimal string. Money never crosses the
/// wire as a JSON float, so a producer and a consumer always agree on the last
/// cent (C0 numbers policy). A JSON number is still accepted on read, because a
/// peer that has not adopted the contract yet should degrade rather than fail.
/// </summary>
public sealed class DecimalStringConverter : JsonConverter<decimal>
{
    /// <inheritdoc />
    public override decimal Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Number) return reader.GetDecimal();
        if (reader.TokenType != JsonTokenType.String)
            throw new JsonException($"decimal must arrive as a JSON string, found {reader.TokenType}.");

        var decoded = Wire.ParseDecimal(reader.GetString()!);
        if (decoded.IsSuccess(out var value)) return value;

        var error = decoded.GetFailure();
        throw new JsonException($"expected {error.Expected}, received \"{error.Actual}\".");
    }

    /// <inheritdoc />
    public override void Write(Utf8JsonWriter writer, decimal value, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(writer);
        writer.WriteStringValue(Wire.Format(value));
    }
}
