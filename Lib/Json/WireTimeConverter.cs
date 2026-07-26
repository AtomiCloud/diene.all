namespace AtomiCloud.Diene.CoreUtils.Json;

/// <summary>Carries a <see cref="TimeOnly" /> as the C0 <c>HH:mm:ss</c> wire form.</summary>
public sealed class WireTimeConverter : WireConverter<TimeOnly>
{
    /// <inheritdoc />
    protected override Result<TimeOnly, WireFormatError> Parse(string wire) => Wire.ParseTime(wire);

    /// <inheritdoc />
    protected override string Format(TimeOnly value) => Wire.Format(value);
}
