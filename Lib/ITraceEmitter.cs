namespace AtomiCloud.Diene.Otel;

/// <summary>
/// The trace EMIT seam. This is a language-local seam rather than one declared in
/// <c>AtomiCloud.Diene.Interfaces</c>: a span carries a shape (events, status,
/// nesting) that the logging and metrics sinks do not, and every language in the
/// family owns the emitter its runtime can honestly implement.
/// </summary>
public interface ITraceEmitter
{
    /// <summary>Delivers one span. Never throws; a rejection is a value.</summary>
    Result<Unit, TraceError> Emit(TraceRecord record);

    /// <summary>Pushes any buffered spans to the exporter.</summary>
    Result<Unit, TraceError> Flush();
}
