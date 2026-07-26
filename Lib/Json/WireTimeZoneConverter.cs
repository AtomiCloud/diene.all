namespace AtomiCloud.Diene.CoreUtils.Json;

/// <summary>
/// Carries a <see cref="TimeZoneInfo" /> as an IANA id. Windows ids and fixed
/// offsets are rejected on read — the contract admits named IANA zones only.
/// </summary>
public sealed class WireTimeZoneConverter : WireConverter<TimeZoneInfo>
{
    /// <inheritdoc />
    protected override Result<TimeZoneInfo, WireFormatError> Parse(string wire) => Wire.ParseTimeZone(wire);

    /// <inheritdoc />
    protected override string Format(TimeZoneInfo value) => Wire.Format(value);
}
