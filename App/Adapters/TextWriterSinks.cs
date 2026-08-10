namespace AtomiCloud.Diene.Interfaces.App.Adapters;

/// <summary>
/// A host-backed reference <see cref="ILoggerSink"/> writing rendered records to a
/// <see cref="TextWriter"/>. <c>AtomiCloud.Diene.Otel</c> ships the real telemetry
/// implementation; this demo adapter exists so the integration tier can run the
/// shipped logger contract against something that performs real IO.
/// </summary>
/// <param name="writer">The destination writer.</param>
public sealed class TextWriterLoggerSink(TextWriter writer) : ILoggerSink
{
    /// <inheritdoc />
    public Result<Unit, SeamError> Emit(LogRecord record)
    {
        if (record is null)
        {
            return SeamErrors.InvalidArgument(SeamKind.Logging, nameof(record), "The record must not be null.");
        }

        try
        {
            writer.WriteLine(Render(record));
            return Result.Ok<Unit, SeamError>(default);
        }
        catch (IOException exception)
        {
            return SeamErrors.EmitFailed(SeamKind.Logging, exception.Message);
        }
        catch (ObjectDisposedException exception)
        {
            return SeamErrors.EmitFailed(SeamKind.Logging, exception.Message);
        }
    }

    private static string Render(LogRecord record)
    {
        var attributes = string.Join(' ', record.Attributes.Select(entry => $"{entry.Key}={entry.Value}"));
        var error = record.Error.Match(value => $" error={value}", () => string.Empty);
        var stack = record.StackTrace.Match(value => $" stack={value}", () => string.Empty);
        return $"{record} {attributes}{error}{stack}".TrimEnd();
    }
}

/// <summary>
/// A host-backed reference <see cref="IMetricsCollector"/> writing rendered samples
/// to a <see cref="TextWriter"/>, for the same reason as
/// <see cref="TextWriterLoggerSink"/>.
/// </summary>
/// <param name="writer">The destination writer.</param>
public sealed class TextWriterMetricsCollector(TextWriter writer) : IMetricsCollector
{
    /// <inheritdoc />
    public Result<Unit, SeamError> Emit(MetricRecord record)
    {
        if (record is null)
        {
            return SeamErrors.InvalidArgument(SeamKind.Metrics, nameof(record), "The record must not be null.");
        }

        try
        {
            writer.WriteLine(Render(record));
            return Result.Ok<Unit, SeamError>(default);
        }
        catch (IOException exception)
        {
            return SeamErrors.EmitFailed(SeamKind.Metrics, exception.Message);
        }
        catch (ObjectDisposedException exception)
        {
            return SeamErrors.EmitFailed(SeamKind.Metrics, exception.Message);
        }
    }

    private static string Render(MetricRecord record)
    {
        var attributes = string.Join(' ', record.Attributes.Select(entry => $"{entry.Key}={entry.Value}"));
        var unit = record.Unit.Match(value => $" unit={value}", () => string.Empty);
        return $"{record}{unit} {attributes}".TrimEnd();
    }
}
