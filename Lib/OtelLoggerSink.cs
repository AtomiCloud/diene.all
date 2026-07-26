using Microsoft.Extensions.Logging;
using MsLogLevel = Microsoft.Extensions.Logging.LogLevel;
using SeamLogLevel = AtomiCloud.Diene.Interfaces.LogLevel;

namespace AtomiCloud.Diene.Otel;

/// <summary>
/// The OpenTelemetry implementation of the structured-logging seam. Attributes
/// travel as a logging scope in their C0 wire form, so a value serialized by this
/// sink is byte-identical to the value the caller emitted, and the emission is
/// total: a hostile record comes back as a <c>SeamError</c>, never as an exception
/// thrown into application code that was only trying to log.
/// </summary>
/// <param name="logger">The host logger the OpenTelemetry provider is attached to.</param>
public sealed class OtelLoggerSink(ILogger logger) : ILoggerSink
{
    /// <summary>The attribute key carrying the record's error description.</summary>
    public const string ErrorKey = "exception.message";

    /// <summary>The attribute key carrying the record's stack trace.</summary>
    public const string StackTraceKey = "exception.stacktrace";

    private readonly ILogger _logger = logger ?? throw new ArgumentNullException(nameof(logger));

    /// <summary>Maps a seam severity onto the host logging severity.</summary>
    public static MsLogLevel Level(SeamLogLevel level) => level switch
    {
        SeamLogLevel.Trace => MsLogLevel.Trace,
        SeamLogLevel.Debug => MsLogLevel.Debug,
        SeamLogLevel.Info => MsLogLevel.Information,
        SeamLogLevel.Warning => MsLogLevel.Warning,
        SeamLogLevel.Error => MsLogLevel.Error,
        SeamLogLevel.Fatal => MsLogLevel.Critical,
        _ => MsLogLevel.None,
    };

    /// <summary>
    /// The scope state a record contributes: every attribute in wire form, plus the
    /// error and stack trace when the record carries them.
    /// </summary>
    public static IReadOnlyList<KeyValuePair<string, object?>> State(LogRecord record)
    {
        ArgumentNullException.ThrowIfNull(record);
        var state = new List<KeyValuePair<string, object?>>(record.Attributes.Count + 2);
        foreach (var (key, value) in record.Attributes) state.Add(new(key, value.Wire));
        if (record.Error.IsSome(out var error)) state.Add(new(ErrorKey, error));
        if (record.StackTrace.IsSome(out var trace)) state.Add(new(StackTraceKey, trace));
        return state;
    }

    /// <inheritdoc />
    public Result<Unit, SeamError> Emit(LogRecord record)
    {
        if (record is null)
        {
            return SeamErrors.InvalidArgument(SeamKind.Logging, nameof(record), "The record must not be null.");
        }

        var level = Level(record.Level);
        if (level == MsLogLevel.None)
        {
            return SeamErrors.InvalidWire("logLevel", record.Level.ToString());
        }

        try
        {
            using (_logger.BeginScope(State(record)))
            {
#pragma warning disable CA2254 // The message IS the caller's data; a compile-time template cannot carry it.
                _logger.Log(level, "{Message}", record.Message);
#pragma warning restore CA2254
            }

            return Result.Ok<Unit, SeamError>(default);
        }
        catch (Exception failure) when (failure is not OutOfMemoryException and not StackOverflowException)
        {
            return SeamErrors.EmitFailed(SeamKind.Logging, failure.Message);
        }
    }
}
