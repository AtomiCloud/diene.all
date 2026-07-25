namespace AtomiCloud.Diene.Interfaces;

/// <summary>The severity of a structured log record. Wire names are lowercase.</summary>
public enum LogLevel
{
    /// <summary>The most detailed diagnostic level.</summary>
    Trace,

    /// <summary>Diagnostic information for development.</summary>
    Debug,

    /// <summary>Normal application progress.</summary>
    Info,

    /// <summary>A recoverable abnormal condition.</summary>
    Warning,

    /// <summary>A failed operation.</summary>
    Error,

    /// <summary>An unrecoverable condition.</summary>
    Fatal,
}

/// <summary>One structured log emission.</summary>
public sealed class LogRecord
{
    /// <summary>Creates a log record, normalizing the timestamp to UTC.</summary>
    /// <param name="timestamp">When the event occurred.</param>
    /// <param name="level">The event severity.</param>
    /// <param name="message">The human-readable event description.</param>
    /// <param name="attributes">Structured context copied into the record.</param>
    /// <param name="error">An optional error description.</param>
    /// <param name="stackTrace">An optional stack trace.</param>
    public LogRecord(
        DateTimeOffset timestamp,
        LogLevel level,
        string message,
        IEnumerable<KeyValuePair<string, AttributeValue>>? attributes = null,
        string? error = null,
        string? stackTrace = null)
    {
        ArgumentNullException.ThrowIfNull(message);
        Timestamp = timestamp.ToUniversalTime();
        Level = level;
        Message = message;
        Attributes = SeamAttributes.Copy(attributes);
        Error = Option.FromNullable(error);
        StackTrace = Option.FromNullable(stackTrace);
    }

    /// <summary>When the event occurred, in UTC.</summary>
    public DateTimeOffset Timestamp { get; }

    /// <summary>The event severity.</summary>
    public LogLevel Level { get; }

    /// <summary>The human-readable event description.</summary>
    public string Message { get; }

    /// <summary>Structured context, ordered by key.</summary>
    public IReadOnlyDictionary<string, AttributeValue> Attributes { get; }

    /// <summary>The error description, when the event carries one.</summary>
    public Option<string> Error { get; }

    /// <summary>The stack trace, when the event carries one.</summary>
    public Option<string> StackTrace { get; }

    /// <summary>Renders the record as <c>instant level message</c>.</summary>
    public override string ToString() => $"{SeamWire.Instant(Timestamp)} {SeamWire.Name(Level)} {Message}";
}

/// <summary>
/// The structured-logging EMIT seam. <c>AtomiCloud.Diene.Otel</c> implements it;
/// this library only declares it, and the shipped TestHelper owns its in-memory
/// mock.
/// </summary>
public interface ILoggerSink
{
    /// <summary>Delivers one log record.</summary>
    Result<Unit, SeamError> Emit(LogRecord record);
}
