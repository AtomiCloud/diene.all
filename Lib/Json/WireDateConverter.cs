namespace AtomiCloud.Diene.CoreUtils.Json;

/// <summary>Carries a <see cref="DateOnly" /> as the C0 <c>YYYY-MM-DD</c> wire form.</summary>
public sealed class WireDateConverter : WireConverter<DateOnly>
{
    /// <inheritdoc />
    protected override Result<DateOnly, WireFormatError> Parse(string wire) => Wire.ParseDate(wire);

    /// <inheritdoc />
    protected override string Format(DateOnly value) => Wire.Format(value);
}
