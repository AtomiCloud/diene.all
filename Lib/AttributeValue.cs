using System.Globalization;

namespace AtomiCloud.Diene.Interfaces;

/// <summary>The closed set of attribute payload shapes carried on the wire.</summary>
public enum AttributeValueKind
{
    /// <summary>An opaque UTF-8 string.</summary>
    Text,

    /// <summary>A 64-bit signed integer.</summary>
    Integer,

    /// <summary>A double-precision number.</summary>
    Real,

    /// <summary>A boolean.</summary>
    Flag,

    /// <summary>An RFC 3339 UTC instant.</summary>
    Instant,

    /// <summary>An ISO 8601 duration.</summary>
    Duration,

    /// <summary>An IANA timezone id.</summary>
    TimeZone,
}

/// <summary>
/// One structured attribute attached to a log or metric record. The value is
/// stored in its C0 wire form, so a record that round-trips through a transport
/// is byte-identical to the record that was emitted, and every date, time,
/// duration, and timezone obeys the R14 serialization contract.
/// </summary>
public readonly struct AttributeValue : IEquatable<AttributeValue>
{
    private readonly string? _wire;

    private AttributeValue(AttributeValueKind kind, string wire)
    {
        Kind = kind;
        _wire = wire;
    }

    /// <summary>The payload shape.</summary>
    public AttributeValueKind Kind { get; }

    /// <summary>The C0 wire form of the payload.</summary>
    public string Wire => _wire ?? string.Empty;

    /// <summary>Creates a text attribute.</summary>
    public static AttributeValue Text(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        return new AttributeValue(AttributeValueKind.Text, value);
    }

    /// <summary>Creates an integer attribute.</summary>
    public static AttributeValue Integer(long value) =>
        new(AttributeValueKind.Integer, value.ToString(CultureInfo.InvariantCulture));

    /// <summary>Creates a real-number attribute.</summary>
    public static AttributeValue Real(double value) =>
        new(AttributeValueKind.Real, value.ToString("R", CultureInfo.InvariantCulture));

    /// <summary>Creates a boolean attribute.</summary>
    public static AttributeValue Flag(bool value) =>
        new(AttributeValueKind.Flag, value ? "true" : "false");

    /// <summary>Creates an instant attribute, normalized to UTC.</summary>
    public static AttributeValue Instant(DateTimeOffset value) =>
        new(AttributeValueKind.Instant, SeamWire.Instant(value));

    /// <summary>Creates an ISO 8601 duration attribute.</summary>
    public static AttributeValue Duration(TimeSpan value) =>
        new(AttributeValueKind.Duration, SeamWire.Duration(value));

    /// <summary>Creates an IANA timezone attribute, rejecting ids the host cannot resolve.</summary>
    public static Result<AttributeValue, SeamError> TimeZone(string id) =>
        SeamWire.TimeZone(id).Map(_ => new AttributeValue(AttributeValueKind.TimeZone, id));

    /// <summary>Rebuilds an attribute from its wire form, validating the payload.</summary>
    public static Result<AttributeValue, SeamError> FromWire(AttributeValueKind kind, string wire) => kind switch
    {
        AttributeValueKind.Text => Result.Ok<AttributeValue, SeamError>(Text(wire)),
        AttributeValueKind.Integer => long.TryParse(wire, CultureInfo.InvariantCulture, out var integer)
            ? Result.Ok<AttributeValue, SeamError>(Integer(integer))
            : SeamErrors.InvalidWire("integer", wire),
        AttributeValueKind.Real => double.TryParse(wire, CultureInfo.InvariantCulture, out var real)
            ? Result.Ok<AttributeValue, SeamError>(Real(real))
            : SeamErrors.InvalidWire("real", wire),
        AttributeValueKind.Flag => ParseFlag(wire),
        AttributeValueKind.Instant => SeamWire.ParseInstant(wire).Map(Instant),
        AttributeValueKind.Duration => SeamWire.ParseDuration(wire).Map(Duration),
        AttributeValueKind.TimeZone => TimeZone(wire),
        _ => SeamErrors.InvalidWire("attributeValueKind", ((int)kind).ToString(CultureInfo.InvariantCulture)),
    };

    /// <summary>Reads the attribute as text, whatever its kind.</summary>
    public string AsText() => Wire;

    /// <summary>Reads the attribute as an integer.</summary>
    public Result<long, SeamError> AsInteger() =>
        Kind == AttributeValueKind.Integer && long.TryParse(Wire, CultureInfo.InvariantCulture, out var value)
            ? Result.Ok<long, SeamError>(value)
            : Mismatch<long>(AttributeValueKind.Integer);

    /// <summary>Reads the attribute as a real number.</summary>
    public Result<double, SeamError> AsReal() =>
        Kind == AttributeValueKind.Real && double.TryParse(Wire, CultureInfo.InvariantCulture, out var value)
            ? Result.Ok<double, SeamError>(value)
            : Mismatch<double>(AttributeValueKind.Real);

    /// <summary>Reads the attribute as a boolean.</summary>
    public Result<bool, SeamError> AsFlag() =>
        Kind == AttributeValueKind.Flag
            ? ParseFlag(Wire).Map(flag => string.Equals(flag.Wire, "true", StringComparison.Ordinal))
            : Mismatch<bool>(AttributeValueKind.Flag);

    /// <summary>Reads the attribute as a UTC instant.</summary>
    public Result<DateTimeOffset, SeamError> AsInstant() =>
        Kind == AttributeValueKind.Instant
            ? SeamWire.ParseInstant(Wire)
            : Mismatch<DateTimeOffset>(AttributeValueKind.Instant);

    /// <summary>Reads the attribute as a duration.</summary>
    public Result<TimeSpan, SeamError> AsDuration() =>
        Kind == AttributeValueKind.Duration
            ? SeamWire.ParseDuration(Wire)
            : Mismatch<TimeSpan>(AttributeValueKind.Duration);

    /// <summary>Resolves the attribute as an IANA timezone.</summary>
    public Result<TimeZoneInfo, SeamError> AsTimeZone() =>
        Kind == AttributeValueKind.TimeZone
            ? SeamWire.TimeZone(Wire)
            : Mismatch<TimeZoneInfo>(AttributeValueKind.TimeZone);

    /// <inheritdoc />
    public bool Equals(AttributeValue other) =>
        Kind == other.Kind && string.Equals(Wire, other.Wire, StringComparison.Ordinal);

    /// <inheritdoc />
    public override bool Equals(object? obj) => obj is AttributeValue other && Equals(other);

    /// <inheritdoc />
    public override int GetHashCode() => HashCode.Combine(Kind, Wire);

    /// <summary>Renders the attribute as <c>kind:wire</c>.</summary>
    public override string ToString() => $"{SeamWire.Name(Kind)}:{Wire}";

    /// <summary>Determines whether two attributes are equal.</summary>
    public static bool operator ==(AttributeValue left, AttributeValue right) => left.Equals(right);

    /// <summary>Determines whether two attributes are unequal.</summary>
    public static bool operator !=(AttributeValue left, AttributeValue right) => !left.Equals(right);

    private static Result<AttributeValue, SeamError> ParseFlag(string wire) =>
        string.Equals(wire, "true", StringComparison.Ordinal) || string.Equals(wire, "false", StringComparison.Ordinal)
            ? Result.Ok<AttributeValue, SeamError>(new AttributeValue(AttributeValueKind.Flag, wire))
            : SeamErrors.InvalidWire("flag", wire);

    private Result<T, SeamError> Mismatch<T>(AttributeValueKind expected) =>
        SeamErrors.InvalidWire(SeamWire.Name(expected), $"{SeamWire.Name(Kind)}:{Wire}");
}
