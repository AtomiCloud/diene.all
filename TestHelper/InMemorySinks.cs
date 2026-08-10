namespace AtomiCloud.Diene.Interfaces.TestHelper;

/// <summary>
/// A recording <see cref="ILoggerSink"/>. This mock is owned by the interfaces
/// TestHelper, not by <c>Otel.TestHelper</c>: any consumer asserting on emitted
/// logs needs it, whether or not an OpenTelemetry pipeline is in play.
/// </summary>
public sealed class InMemoryLoggerSink : ILoggerSink
{
    private readonly Lock _gate = new();
    private readonly List<LogRecord> _records = [];
    private readonly Queue<SeamError> _failures = new();

    /// <summary>The records this sink accepted, in emit order.</summary>
    public IReadOnlyList<LogRecord> Records
    {
        get
        {
            lock (_gate) return [.. _records];
        }
    }

    /// <summary>Queues one failure to be returned by the next emit.</summary>
    public void EnqueueFailure(SeamError error)
    {
        ArgumentNullException.ThrowIfNull(error);
        lock (_gate) _failures.Enqueue(error);
    }

    /// <inheritdoc />
    public Result<Unit, SeamError> Emit(LogRecord record)
    {
        if (record is null)
        {
            return SeamErrors.InvalidArgument(SeamKind.Logging, nameof(record), "The record must not be null.");
        }

        lock (_gate)
        {
            if (_failures.TryDequeue(out var failure)) return failure;
            _records.Add(record);
            return Result.Ok<Unit, SeamError>(default);
        }
    }
}

/// <summary>
/// A recording <see cref="IMetricsCollector"/>, owned by the interfaces
/// TestHelper for the same reason as <see cref="InMemoryLoggerSink"/>.
/// </summary>
public sealed class InMemoryMetricsCollector : IMetricsCollector
{
    private readonly Lock _gate = new();
    private readonly List<MetricRecord> _records = [];
    private readonly Queue<SeamError> _failures = new();

    /// <summary>The samples this collector accepted, in emit order.</summary>
    public IReadOnlyList<MetricRecord> Records
    {
        get
        {
            lock (_gate) return [.. _records];
        }
    }

    /// <summary>Queues one failure to be returned by the next emit.</summary>
    public void EnqueueFailure(SeamError error)
    {
        ArgumentNullException.ThrowIfNull(error);
        lock (_gate) _failures.Enqueue(error);
    }

    /// <inheritdoc />
    public Result<Unit, SeamError> Emit(MetricRecord record)
    {
        if (record is null)
        {
            return SeamErrors.InvalidArgument(SeamKind.Metrics, nameof(record), "The record must not be null.");
        }

        lock (_gate)
        {
            if (_failures.TryDequeue(out var failure)) return failure;
            _records.Add(record);
            return Result.Ok<Unit, SeamError>(default);
        }
    }
}
