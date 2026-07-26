namespace AtomiCloud.Diene.Otel;

/// <summary>
/// The wire names of the trace seam's enumerations. Every name is shared with the
/// bun member of the same seam family, so a span serialized by one language reads
/// identically in another.
/// </summary>
public static class TraceWire
{
    /// <summary>The wire name of a span outcome.</summary>
    public static string Name(TraceStatus value) => value switch
    {
        TraceStatus.Unset => "unset",
        TraceStatus.Ok => "ok",
        TraceStatus.Error => "error",
        _ => throw new ArgumentOutOfRangeException(nameof(value), value, "Unmapped TraceStatus wire name."),
    };

    /// <summary>The wire name of a trace failure code.</summary>
    public static string Name(TraceErrorCode value) => value switch
    {
        TraceErrorCode.InvalidInput => "invalid-input",
        TraceErrorCode.Io => "io",
        TraceErrorCode.Unavailable => "unavailable",
        TraceErrorCode.UnexpectedCall => "unexpected-call",
        _ => throw new ArgumentOutOfRangeException(nameof(value), value, "Unmapped TraceErrorCode wire name."),
    };

    /// <summary>Parses a span outcome wire name.</summary>
    public static Result<TraceStatus, TraceError> ParseStatus(string value) =>
        Parse<TraceStatus>("status", value, Name);

    /// <summary>Parses a trace failure code wire name.</summary>
    public static Result<TraceErrorCode, TraceError> ParseErrorCode(string value) =>
        Parse<TraceErrorCode>("code", value, Name);

    private static Result<TEnum, TraceError> Parse<TEnum>(string field, string value, Func<TEnum, string> name)
        where TEnum : struct, Enum
    {
        foreach (var candidate in Enum.GetValues<TEnum>())
        {
            if (string.Equals(name(candidate), value, StringComparison.Ordinal))
            {
                return Result.Ok<TEnum, TraceError>(candidate);
            }
        }

        return TraceErrors.InvalidInput("parse", $"'{value}' is not a valid trace {field} wire name.");
    }
}
