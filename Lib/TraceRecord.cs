using System.Collections.Immutable;

namespace AtomiCloud.Diene.Otel;

/// <summary>The outcome a span reports. Wire names are lowercase.</summary>
public enum TraceStatus
{
    /// <summary>No explicit outcome was set.</summary>
    Unset,

    /// <summary>The operation succeeded.</summary>
    Ok,

    /// <summary>The operation failed.</summary>
    Error,
}

/// <summary>One timestamped annotation inside a span.</summary>
public sealed class TraceEvent : IEquatable<TraceEvent>
{
    private TraceEvent(string name, IReadOnlyDictionary<string, AttributeValue> attributes)
    {
        Name = name;
        Attributes = attributes;
    }

    /// <summary>The event name.</summary>
    public string Name { get; }

    /// <summary>Structured context, ordered by key.</summary>
    public IReadOnlyDictionary<string, AttributeValue> Attributes { get; }

    /// <summary>
    /// Validates and builds an event. Construction is total: a rejected event is a
    /// <see cref="TraceError" /> value, never an exception.
    /// </summary>
    public static Result<TraceEvent, TraceError> Create(
        string? name,
        IEnumerable<KeyValuePair<string, AttributeValue>>? attributes = null) =>
        string.IsNullOrWhiteSpace(name)
            ? TraceErrors.InvalidInput("emit", "Trace event names must not be blank.")
            : TraceAttributes.Check(attributes, "emit").Map(checked_ => new TraceEvent(name, checked_));

    /// <inheritdoc />
    public bool Equals(TraceEvent? other) =>
        other is not null &&
        string.Equals(Name, other.Name, StringComparison.Ordinal) &&
        TraceAttributes.Equal(Attributes, other.Attributes);

    /// <inheritdoc />
    public override bool Equals(object? obj) => Equals(obj as TraceEvent);

    /// <inheritdoc />
    public override int GetHashCode() => HashCode.Combine(Name, Attributes.Count);

    /// <summary>Renders the event as its name.</summary>
    public override string ToString() => Name;
}

/// <summary>
/// One span emitted through the trace seam. The record is validated at
/// construction and immutable afterwards, so an emitter can never observe a
/// half-built span or mutate a caller's data.
/// </summary>
public sealed class TraceRecord : IEquatable<TraceRecord>
{
    private TraceRecord(
        string name,
        IReadOnlyDictionary<string, AttributeValue> attributes,
        IReadOnlyList<TraceEvent> events,
        TraceStatus status,
        Option<string> statusMessage)
    {
        Name = name;
        Attributes = attributes;
        Events = events;
        Status = status;
        StatusMessage = statusMessage;
    }

    /// <summary>The span name.</summary>
    public string Name { get; }

    /// <summary>Structured context, ordered by key.</summary>
    public IReadOnlyDictionary<string, AttributeValue> Attributes { get; }

    /// <summary>The annotations recorded inside the span, in emission order.</summary>
    public IReadOnlyList<TraceEvent> Events { get; }

    /// <summary>The reported outcome.</summary>
    public TraceStatus Status { get; }

    /// <summary>The outcome description, when the span carries one.</summary>
    public Option<string> StatusMessage { get; }

    /// <summary>
    /// Validates and builds a span record. A blank name, a blank status message, an
    /// unrecognized status, or a hostile attribute map is rejected as a value.
    /// </summary>
    public static Result<TraceRecord, TraceError> Create(
        string? name,
        IEnumerable<KeyValuePair<string, AttributeValue>>? attributes = null,
        IEnumerable<TraceEvent>? events = null,
        TraceStatus status = TraceStatus.Unset,
        string? statusMessage = null)
    {
        if (string.IsNullOrWhiteSpace(name)) return TraceErrors.InvalidInput("emit", "Trace name must not be blank.");
        if (!Enum.IsDefined(status)) return TraceErrors.InvalidInput("emit", "Trace status is invalid.");
        if (statusMessage is not null && string.IsNullOrWhiteSpace(statusMessage))
        {
            return TraceErrors.InvalidInput("emit", "Trace status message must not be blank.");
        }

        var recorded = events is null ? [] : events.ToImmutableArray();
        return recorded.Contains(null!)
            ? TraceErrors.InvalidInput("emit", "Trace events must not be null.")
            : TraceAttributes
                .Check(attributes, "emit")
                .Map(checked_ => new TraceRecord(
                    name,
                    checked_,
                    recorded,
                    status,
                    Option.FromNullable(statusMessage)));
    }

    /// <inheritdoc />
    public bool Equals(TraceRecord? other) =>
        other is not null &&
        string.Equals(Name, other.Name, StringComparison.Ordinal) &&
        Status == other.Status &&
        StatusMessage == other.StatusMessage &&
        TraceAttributes.Equal(Attributes, other.Attributes) &&
        Events.SequenceEqual(other.Events);

    /// <inheritdoc />
    public override bool Equals(object? obj) => Equals(obj as TraceRecord);

    /// <inheritdoc />
    public override int GetHashCode() => HashCode.Combine(Name, Status, Attributes.Count, Events.Count);

    /// <summary>Renders the record as <c>name status</c>.</summary>
    public override string ToString() => $"{Name} {TraceWire.Name(Status)}";
}
