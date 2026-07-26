using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace AtomiCloud.Diene.CoreUtils;

/// <summary>
/// The C0 §1 serialization contract as Result-returning codecs, for the call
/// sites that are not System.Text.Json: config values, CLI arguments, headers,
/// and tests. JSON payloads get the same forms through
/// <see cref="Json.AtomiJson" />.
/// </summary>
/// <remarks>
/// Domain code keeps native temporal types; only the transport sees strings.
/// This split is what kills the bespoke-format bug class (<c>ZincDate</c>'s
/// DD-MM-YYYY): there is exactly one spelling of each form and one place that
/// produces it.
/// </remarks>
public static class Wire
{
    /// <summary>The canonical wire spelling of a date.</summary>
    public const string DateFormat = "yyyy-MM-dd";

    /// <summary>The canonical wire spelling of a time of day.</summary>
    public const string TimeFormat = "HH:mm:ss";

    private const int MaxFractionDigits = 7;

    /// <summary>Parses a C0 date (<c>YYYY-MM-DD</c>).</summary>
    public static Result<DateOnly, WireFormatError> ParseDate(string s)
    {
        ArgumentNullException.ThrowIfNull(s);
        return DateOnly.TryParseExact(s, DateFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)
            ? Result.Ok<DateOnly, WireFormatError>(date)
            : Result.Err<DateOnly, WireFormatError>(new WireFormatError(DateFormat, s));
    }

    /// <summary>Parses a C0 time of day (<c>HH:mm:ss</c>, whole seconds, no offset).</summary>
    public static Result<TimeOnly, WireFormatError> ParseTime(string s)
    {
        ArgumentNullException.ThrowIfNull(s);
        return TimeOnly.TryParseExact(s, TimeFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out var time)
            ? Result.Ok<TimeOnly, WireFormatError>(time)
            : Result.Err<TimeOnly, WireFormatError>(new WireFormatError(TimeFormat, s));
    }

    /// <summary>
    /// Parses an RFC 3339 instant. A trailing offset is accepted and normalized to
    /// UTC; fractional digits below tick precision are truncated.
    /// </summary>
    public static Result<DateTimeOffset, WireFormatError> ParseInstant(string s)
    {
        ArgumentNullException.ThrowIfNull(s);

        var match = InstantRegex.Match(s);
        if (!match.Success) return InstantError(s);

        var fraction = match.Groups["fraction"].Value;
        var truncated = fraction.Length > MaxFractionDigits + 1
            ? fraction[..(MaxFractionDigits + 1)]
            : fraction;
        // RFC 3339 permits a lowercase separator and designator; the canonical
        // spelling this library emits is uppercase, so fold before parsing.
        var stamp = match.Groups["stamp"].Value;
        var offset = match.Groups["offset"].Value;
        var normalized = string.Concat(
            stamp[..10],
            "T",
            stamp[11..],
            truncated,
            offset.Length == 1 ? "+00:00" : offset);

        return DateTimeOffset.TryParseExact(
            normalized,
            "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFzzz",
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out var instant)
            ? Result.Ok<DateTimeOffset, WireFormatError>(instant.ToUniversalTime())
            : InstantError(s);
    }

    /// <summary>
    /// Parses an ISO 8601 duration. Time-based components and whole days are
    /// supported; calendar years, months, and weeks are out of scope because they
    /// have no fixed length.
    /// </summary>
    public static Result<TimeSpan, WireFormatError> ParseDuration(string s)
    {
        ArgumentNullException.ThrowIfNull(s);

        var match = DurationRegex.Match(s);
        if (!match.Success) return DurationError(s);

        var days = match.Groups["days"];
        var hours = match.Groups["hours"];
        var minutes = match.Groups["minutes"];
        var seconds = match.Groups["seconds"];
        if (!days.Success && !hours.Success && !minutes.Success && !seconds.Success) return DurationError(s);

        var total = TimeSpan.Zero;
        if (days.Success) total += TimeSpan.FromDays(long.Parse(days.Value, CultureInfo.InvariantCulture));
        if (hours.Success) total += TimeSpan.FromHours(long.Parse(hours.Value, CultureInfo.InvariantCulture));
        if (minutes.Success) total += TimeSpan.FromMinutes(long.Parse(minutes.Value, CultureInfo.InvariantCulture));
        if (seconds.Success)
        {
            var value = decimal.Parse(seconds.Value, CultureInfo.InvariantCulture);
            total += TimeSpan.FromTicks((long)(value * TimeSpan.TicksPerSecond));
        }

        return Result.Ok<TimeSpan, WireFormatError>(match.Groups["sign"].Success ? -total : total);
    }

    /// <summary>
    /// Resolves an IANA timezone id against the host database. Windows ids and
    /// fixed offsets are rejected: the contract is IANA-only.
    /// </summary>
    public static Result<TimeZoneInfo, WireFormatError> ParseTimeZone(string s)
    {
        ArgumentNullException.ThrowIfNull(s);
        return TimeZoneInfo.TryFindSystemTimeZoneById(s, out var zone) && zone.HasIanaId
            ? Result.Ok<TimeZoneInfo, WireFormatError>(zone)
            : Result.Err<TimeZoneInfo, WireFormatError>(new WireFormatError("IANA timezone id", s));
    }

    /// <summary>Renders a date in the canonical wire form.</summary>
    public static string Format(DateOnly value) => value.ToString(DateFormat, CultureInfo.InvariantCulture);

    /// <summary>Renders a time of day in the canonical wire form, truncated to whole seconds.</summary>
    public static string Format(TimeOnly value) => value.ToString(TimeFormat, CultureInfo.InvariantCulture);

    /// <summary>Renders an instant as an RFC 3339 UTC timestamp, always with a <c>Z</c> designator.</summary>
    public static string Format(DateTimeOffset value)
    {
        var utc = value.ToUniversalTime();
        var fraction = utc.Ticks % TimeSpan.TicksPerSecond;
        var stamp = utc.ToString("yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture);
        if (fraction == 0) return $"{stamp}Z";

        var digits = fraction.ToString("D7", CultureInfo.InvariantCulture).TrimEnd('0');
        return $"{stamp}.{digits}Z";
    }

    /// <summary>Renders a duration in the canonical ISO 8601 spelling.</summary>
    public static string Format(TimeSpan value)
    {
        if (value == TimeSpan.Zero) return "PT0S";

        var magnitude = value.Duration();
        var rendered = new StringBuilder(value < TimeSpan.Zero ? "-P" : "P");

        var days = (long)magnitude.TotalDays;
        if (days > 0) rendered.Append(days).Append('D');

        var hours = magnitude.Hours;
        var minutes = magnitude.Minutes;
        var secondTicks = magnitude.Ticks % TimeSpan.TicksPerMinute;
        if (hours == 0 && minutes == 0 && secondTicks == 0) return rendered.ToString();

        rendered.Append('T');
        if (hours > 0) rendered.Append(hours).Append('H');
        if (minutes > 0) rendered.Append(minutes).Append('M');
        if (secondTicks > 0) rendered.Append(FormatSeconds(secondTicks)).Append('S');

        return rendered.ToString();
    }

    /// <summary>Renders a validated timezone as its IANA id.</summary>
    public static string Format(TimeZoneInfo value)
    {
        ArgumentNullException.ThrowIfNull(value);
        return value.Id;
    }

    /// <summary>
    /// Renders a decimal as a decimal string. Money and other exact quantities
    /// cross the wire as strings, never as JSON floats (C0 numbers policy).
    /// </summary>
    public static string Format(decimal value) => value.ToString(CultureInfo.InvariantCulture);

    /// <summary>
    /// Renders a 64-bit integer as a decimal string, because values beyond the
    /// IEEE-754 safe range do not survive a JSON number.
    /// </summary>
    public static string Format(long value) => value.ToString(CultureInfo.InvariantCulture);

    /// <summary>Parses a decimal carried as a decimal string.</summary>
    public static Result<decimal, WireFormatError> ParseDecimal(string s)
    {
        ArgumentNullException.ThrowIfNull(s);
        return DecimalRegex.IsMatch(s)
            && decimal.TryParse(s, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
                CultureInfo.InvariantCulture, out var value)
            ? Result.Ok<decimal, WireFormatError>(value)
            : Result.Err<decimal, WireFormatError>(new WireFormatError("decimal string", s));
    }

    /// <summary>Parses a 64-bit integer carried as a decimal string.</summary>
    public static Result<long, WireFormatError> ParseInt64(string s)
    {
        ArgumentNullException.ThrowIfNull(s);
        return long.TryParse(s, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var value)
            ? Result.Ok<long, WireFormatError>(value)
            : Result.Err<long, WireFormatError>(new WireFormatError("int64 string", s));
    }

    private static string FormatSeconds(long ticks)
    {
        var whole = ticks / TimeSpan.TicksPerSecond;
        var fraction = ticks % TimeSpan.TicksPerSecond;
        if (fraction == 0) return whole.ToString(CultureInfo.InvariantCulture);

        var digits = fraction.ToString("D7", CultureInfo.InvariantCulture).TrimEnd('0');
        return $"{whole.ToString(CultureInfo.InvariantCulture)}.{digits}";
    }

    private static Result<DateTimeOffset, WireFormatError> InstantError(string s) =>
        Result.Err<DateTimeOffset, WireFormatError>(new WireFormatError("RFC 3339 instant", s));

    private static Result<TimeSpan, WireFormatError> DurationError(string s) =>
        Result.Err<TimeSpan, WireFormatError>(new WireFormatError("ISO 8601 duration", s));

    // Interpreted rather than source-generated: the generator emits a state
    // machine whose unreachable arms no test can drive, and a coverage exclusion
    // list to hide them would be a worse trade than the parse cost on these
    // config-and-header-sized inputs.
    private static readonly Regex InstantRegex = new(
        @"^(?<stamp>\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2})(?<fraction>\.\d{1,9})?(?<offset>[Zz]|[+-]\d{2}:\d{2})$",
        RegexOptions.CultureInvariant);

    private static readonly Regex DurationRegex = new(
        @"^(?<sign>-)?P(?:(?<days>\d+)D)?(?:T(?:(?<hours>\d+)H)?(?:(?<minutes>\d+)M)?(?:(?<seconds>\d+(?:\.\d{1,7})?)S)?)?$",
        RegexOptions.CultureInvariant);

    private static readonly Regex DecimalRegex = new(@"^-?\d+(?:\.\d+)?$", RegexOptions.CultureInvariant);
}
