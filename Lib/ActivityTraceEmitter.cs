using System.Diagnostics;

namespace AtomiCloud.Diene.Otel;

/// <summary>
/// The real trace emitter: it turns a validated <see cref="TraceRecord" /> into an
/// <see cref="Activity" /> on the app-scoped source. When nothing is listening the
/// source returns no activity and the emit is a successful no-op — a service with
/// tracing disabled must not fail its own work.
/// </summary>
/// <param name="instrumentation">The app-scoped activity source to emit through.</param>
public sealed class ActivityTraceEmitter(Instrumentation instrumentation) : ITraceEmitter
{
    private readonly Instrumentation _instrumentation =
        instrumentation ?? throw new ArgumentNullException(nameof(instrumentation));

    /// <inheritdoc />
    public Result<Unit, TraceError> Emit(TraceRecord record)
    {
        if (record is null) return TraceErrors.InvalidInput("emit", "The trace record must not be null.");

        using var activity = _instrumentation.ActivitySource.StartActivity(record.Name);
        if (activity is null) return Result.Ok<Unit, TraceError>(default);

        foreach (var (key, value) in record.Attributes) activity.SetTag(key, value.Wire);

        foreach (var recorded in record.Events)
        {
            var tags = new ActivityTagsCollection();
            foreach (var (key, value) in recorded.Attributes) tags[key] = value.Wire;
            activity.AddEvent(new ActivityEvent(recorded.Name, tags: tags));
        }

        activity.SetStatus(Status(record.Status), record.StatusMessage.ToNullable());
        return Result.Ok<Unit, TraceError>(default);
    }

    /// <inheritdoc />
    public Result<Unit, TraceError> Flush() => Result.Ok<Unit, TraceError>(default);

    private static ActivityStatusCode Status(TraceStatus status) => status switch
    {
        TraceStatus.Ok => ActivityStatusCode.Ok,
        TraceStatus.Error => ActivityStatusCode.Error,
        _ => ActivityStatusCode.Unset,
    };
}
