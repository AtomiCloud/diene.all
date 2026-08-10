namespace AtomiCloud.Diene.CoreUtils.Json;

/// <summary>Carries a <see cref="TimeSpan" /> as an ISO 8601 duration.</summary>
public sealed class WireDurationConverter : WireConverter<TimeSpan>
{
    /// <inheritdoc />
    protected override Result<TimeSpan, WireFormatError> Parse(string wire) => Wire.ParseDuration(wire);

    /// <inheritdoc />
    protected override string Format(TimeSpan value) => Wire.Format(value);
}
