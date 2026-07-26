namespace AtomiCloud.Diene.CoreUtils.Json;

/// <summary>
/// Carries a <see cref="DateTimeOffset" /> as an RFC 3339 UTC instant. Reading
/// accepts a trailing offset and normalizes it; writing always emits <c>Z</c>.
/// </summary>
public sealed class WireInstantConverter : WireConverter<DateTimeOffset>
{
    /// <inheritdoc />
    protected override Result<DateTimeOffset, WireFormatError> Parse(string wire) => Wire.ParseInstant(wire);

    /// <inheritdoc />
    protected override string Format(DateTimeOffset value) => Wire.Format(value);
}
