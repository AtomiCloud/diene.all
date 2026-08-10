using System.Globalization;
using System.Xml;

namespace AtomiCloud.Diene.Interfaces;

/// <summary>
/// The C0 wire contract for seam values (R14): instants are RFC 3339 / ISO 8601
/// in UTC, durations are ISO 8601 durations, timezones are IANA ids, and every
/// enumeration has one stable lowercase wire name shared with the bun, dart, and
/// go members of the same S33 interfaces family.
/// </summary>
public static class SeamWire
{
    /// <summary>The RFC 3339 instant format this contract emits, always UTC.</summary>
    public const string InstantFormat = "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'";

    private static readonly string[] InstantParseFormats =
    [
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'",
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFzzz",
        "yyyy-MM-dd'T'HH:mm:sszzz",
    ];

    /// <summary>Renders an instant as an RFC 3339 UTC timestamp.</summary>
    public static string Instant(DateTimeOffset value) =>
        value.ToUniversalTime().ToString(InstantFormat, CultureInfo.InvariantCulture);

    /// <summary>Parses an RFC 3339 timestamp and normalizes it to UTC.</summary>
    public static Result<DateTimeOffset, SeamError> ParseInstant(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return SeamErrors.InvalidWire("instant", value);
        return DateTimeOffset.TryParseExact(
            value,
            InstantParseFormats,
            CultureInfo.InvariantCulture,
            DateTimeStyles.RoundtripKind,
            out var parsed)
            ? Result.Ok<DateTimeOffset, SeamError>(parsed.ToUniversalTime())
            : SeamErrors.InvalidWire("instant", value);
    }

    /// <summary>Renders a duration as an ISO 8601 duration.</summary>
    public static string Duration(TimeSpan value) => XmlConvert.ToString(value);

    /// <summary>Parses an ISO 8601 duration.</summary>
    public static Result<TimeSpan, SeamError> ParseDuration(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return SeamErrors.InvalidWire("duration", value);
        try
        {
            return Result.Ok<TimeSpan, SeamError>(XmlConvert.ToTimeSpan(value));
        }
        catch (FormatException)
        {
            return SeamErrors.InvalidWire("duration", value);
        }
        catch (OverflowException)
        {
            return SeamErrors.InvalidWire("duration", value);
        }
    }

    /// <summary>Resolves an IANA timezone id against the host timezone database.</summary>
    public static Result<TimeZoneInfo, SeamError> TimeZone(string id)
    {
        if (string.IsNullOrWhiteSpace(id)) return SeamErrors.InvalidWire("timeZone", id ?? string.Empty);
        return TimeZoneInfo.TryFindSystemTimeZoneById(id, out var zone)
            ? Result.Ok<TimeZoneInfo, SeamError>(zone)
            : SeamErrors.UnknownTimeZone(id, $"The host timezone database has no entry for '{id}'.");
    }

    /// <summary>The wire name of a seam.</summary>
    public static string Name(SeamKind value) => value switch
    {
        SeamKind.System => "system",
        SeamKind.Vfs => "vfs",
        SeamKind.Terminal => "terminal",
        SeamKind.Logging => "logging",
        SeamKind.Metrics => "metrics",
        _ => Unknown(value),
    };

    /// <summary>The wire name of a log level.</summary>
    public static string Name(LogLevel value) => value switch
    {
        LogLevel.Trace => "trace",
        LogLevel.Debug => "debug",
        LogLevel.Info => "info",
        LogLevel.Warning => "warning",
        LogLevel.Error => "error",
        LogLevel.Fatal => "fatal",
        _ => Unknown(value),
    };

    /// <summary>The wire name of a metric kind.</summary>
    public static string Name(MetricKind value) => value switch
    {
        MetricKind.Counter => "counter",
        MetricKind.Gauge => "gauge",
        MetricKind.Histogram => "histogram",
        _ => Unknown(value),
    };

    /// <summary>The wire name of a filesystem entry type.</summary>
    public static string Name(VfsEntryType value) => value switch
    {
        VfsEntryType.File => "file",
        VfsEntryType.Directory => "directory",
        VfsEntryType.Link => "link",
        _ => Unknown(value),
    };

    /// <summary>The wire name of an attribute value kind.</summary>
    public static string Name(AttributeValueKind value) => value switch
    {
        AttributeValueKind.Text => "text",
        AttributeValueKind.Integer => "integer",
        AttributeValueKind.Real => "real",
        AttributeValueKind.Flag => "flag",
        AttributeValueKind.Instant => "instant",
        AttributeValueKind.Duration => "duration",
        AttributeValueKind.TimeZone => "time_zone",
        _ => Unknown(value),
    };

    /// <summary>Parses a seam wire name.</summary>
    public static Result<SeamKind, SeamError> ParseSeamKind(string value) =>
        Parse<SeamKind>("seam", value, Name);

    /// <summary>Parses a log level wire name.</summary>
    public static Result<LogLevel, SeamError> ParseLogLevel(string value) =>
        Parse<LogLevel>("logLevel", value, Name);

    /// <summary>Parses a metric kind wire name.</summary>
    public static Result<MetricKind, SeamError> ParseMetricKind(string value) =>
        Parse<MetricKind>("metricKind", value, Name);

    /// <summary>Parses a filesystem entry type wire name.</summary>
    public static Result<VfsEntryType, SeamError> ParseVfsEntryType(string value) =>
        Parse<VfsEntryType>("vfsEntryType", value, Name);

    /// <summary>Parses an attribute value kind wire name.</summary>
    public static Result<AttributeValueKind, SeamError> ParseAttributeValueKind(string value) =>
        Parse<AttributeValueKind>("attributeValueKind", value, Name);

    private static Result<TEnum, SeamError> Parse<TEnum>(string field, string value, Func<TEnum, string> name)
        where TEnum : struct, Enum
    {
        foreach (var candidate in Enum.GetValues<TEnum>())
        {
            if (string.Equals(name(candidate), value, StringComparison.Ordinal))
            {
                return Result.Ok<TEnum, SeamError>(candidate);
            }
        }

        return SeamErrors.InvalidWire(field, value);
    }

    private static string Unknown<TEnum>(TEnum value)
        where TEnum : struct, Enum =>
        throw new ArgumentOutOfRangeException(nameof(value), value, $"Unmapped {typeof(TEnum).Name} wire name.");
}
