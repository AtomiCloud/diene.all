namespace AtomiCloud.Diene.Otel.TestHelper;

/// <summary>The trace-seam method a recorded call went through.</summary>
public enum TraceCallKind
{
    /// <summary>A span was emitted.</summary>
    Emit,

    /// <summary>A flush was requested.</summary>
    Flush,
}

/// <summary>One recorded trace-seam call, in the order it arrived.</summary>
/// <param name="Sequence">The zero-based position of the call.</param>
/// <param name="Kind">Which seam method was called.</param>
/// <param name="Record">The span, present only on an emit.</param>
public sealed record TraceCall(int Sequence, TraceCallKind Kind, Option<TraceRecord> Record);

/// <summary>
/// A recording <see cref="ITraceEmitter" />. Every call is captured — including the
/// ones that fail — so a test can assert what the subject TRIED to emit, not only
/// what got through. Failures are scripted through <see cref="FailNext" /> rather
/// than a mocking framework, so a test names the failure it wants.
/// </summary>
public sealed class InMemoryTraceEmitter : ITraceEmitter
{
    private readonly List<TraceCall> _calls = [];
    private readonly Queue<TraceError> _failures = new();
    private readonly Lock _gate = new();
    private readonly List<TraceRecord> _records = [];

    /// <summary>Every call the emitter received, in order, failures included.</summary>
    public IReadOnlyList<TraceCall> Calls
    {
        get
        {
            lock (_gate) return [.. _calls];
        }
    }

    /// <summary>The spans this emitter accepted, in emit order.</summary>
    public IReadOnlyList<TraceRecord> Records
    {
        get
        {
            lock (_gate) return [.. _records];
        }
    }

    /// <summary>How many times a flush was requested.</summary>
    public int Flushes
    {
        get
        {
            lock (_gate) return _calls.Count(call => call.Kind == TraceCallKind.Flush);
        }
    }

    /// <summary>Queues one failure, returned by the next seam call and then discarded.</summary>
    public void FailNext(TraceError error)
    {
        ArgumentNullException.ThrowIfNull(error);
        lock (_gate) _failures.Enqueue(error);
    }

    /// <summary>The accepted spans carrying an exact name, in emit order.</summary>
    public IReadOnlyList<TraceRecord> Named(string name)
    {
        ArgumentNullException.ThrowIfNull(name);
        lock (_gate) return [.. _records.Where(record => string.Equals(record.Name, name, StringComparison.Ordinal))];
    }

    /// <summary>Discards every recorded call and span.</summary>
    public void Clear()
    {
        lock (_gate)
        {
            _calls.Clear();
            _records.Clear();
            _failures.Clear();
        }
    }

    /// <inheritdoc />
    public Result<Unit, TraceError> Emit(TraceRecord record)
    {
        if (record is null) return TraceErrors.InvalidInput("emit", "The trace record must not be null.");

        lock (_gate)
        {
            _calls.Add(new TraceCall(_calls.Count, TraceCallKind.Emit, Option.Some(record)));
            if (_failures.TryDequeue(out var failure)) return failure;
            _records.Add(record);
            return Result.Ok<Unit, TraceError>(default);
        }
    }

    /// <inheritdoc />
    public Result<Unit, TraceError> Flush()
    {
        lock (_gate)
        {
            _calls.Add(new TraceCall(_calls.Count, TraceCallKind.Flush, Option.None<TraceRecord>()));
            return _failures.TryDequeue(out var failure)
                ? failure
                : Result.Ok<Unit, TraceError>(default);
        }
    }
}
