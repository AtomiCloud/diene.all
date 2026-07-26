using System.Collections.Immutable;

namespace AtomiCloud.Diene.Otel;

/// <summary>Why a trace-seam call failed. Wire names are lowercase-hyphen.</summary>
public enum TraceErrorCode
{
    /// <summary>The record or attribute map did not satisfy the seam's invariants.</summary>
    InvalidInput,

    /// <summary>The underlying exporter or transport failed.</summary>
    Io,

    /// <summary>The emitter is not accepting spans right now.</summary>
    Unavailable,

    /// <summary>The emitter was called in a way its contract does not allow.</summary>
    UnexpectedCall,
}

/// <summary>
/// The failure channel of the trace seam. Like <c>SeamError</c> in the interfaces
/// family, this is a value rather than an exception: emitting a span never throws.
/// </summary>
public sealed class TraceError : IEquatable<TraceError>
{
    private readonly ImmutableSortedDictionary<string, string> _details;

    /// <summary>Creates a trace error.</summary>
    /// <param name="code">The machine-readable failure code.</param>
    /// <param name="operation">The seam operation that failed.</param>
    /// <param name="message">The human-readable failure description.</param>
    /// <param name="details">Optional structured context copied into the error.</param>
    public TraceError(
        TraceErrorCode code,
        string operation,
        string message,
        IEnumerable<KeyValuePair<string, string>>? details = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(operation);
        ArgumentNullException.ThrowIfNull(message);
        Code = code;
        Operation = operation;
        Message = message;
        _details = details is null
            ? ImmutableSortedDictionary<string, string>.Empty
            : ImmutableSortedDictionary.CreateRange(StringComparer.Ordinal, details);
    }

    /// <summary>The machine-readable failure code.</summary>
    public TraceErrorCode Code { get; }

    /// <summary>The seam operation that failed.</summary>
    public string Operation { get; }

    /// <summary>The human-readable failure description.</summary>
    public string Message { get; }

    /// <summary>Structured context, ordered by key.</summary>
    public IReadOnlyDictionary<string, string> Details => _details;

    /// <summary>Returns a copy carrying one additional context entry.</summary>
    public TraceError With(string key, string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        ArgumentNullException.ThrowIfNull(value);
        return new TraceError(Code, Operation, Message, _details.SetItem(key, value));
    }

    /// <inheritdoc />
    public bool Equals(TraceError? other) =>
        other is not null &&
        Code == other.Code &&
        string.Equals(Operation, other.Operation, StringComparison.Ordinal) &&
        string.Equals(Message, other.Message, StringComparison.Ordinal) &&
        _details.Count == other._details.Count &&
        _details.SequenceEqual(other._details);

    /// <inheritdoc />
    public override bool Equals(object? obj) => Equals(obj as TraceError);

    /// <inheritdoc />
    public override int GetHashCode() => HashCode.Combine(Code, Operation, Message, _details.Count);

    /// <summary>Renders the error as <c>code/operation: message</c>.</summary>
    public override string ToString() => $"{TraceWire.Name(Code)}/{Operation}: {Message}";

    /// <summary>Determines whether two trace errors are equal.</summary>
    public static bool operator ==(TraceError? left, TraceError? right) =>
        left is null ? right is null : left.Equals(right);

    /// <summary>Determines whether two trace errors are unequal.</summary>
    public static bool operator !=(TraceError? left, TraceError? right) => !(left == right);
}

/// <summary>The trace-seam failure catalog. Every emitter reports through these.</summary>
public static class TraceErrors
{
    /// <summary>The record or attribute map violated a seam invariant.</summary>
    public static TraceError InvalidInput(string operation, string message) =>
        new(TraceErrorCode.InvalidInput, operation, message);

    /// <summary>The exporter or transport failed.</summary>
    public static TraceError Io(string operation, string message) =>
        new(TraceErrorCode.Io, operation, message);

    /// <summary>The emitter is not accepting spans.</summary>
    public static TraceError Unavailable(string operation, string message) =>
        new(TraceErrorCode.Unavailable, operation, message);

    /// <summary>The emitter's contract was called incorrectly.</summary>
    public static TraceError UnexpectedCall(string operation, string message) =>
        new(TraceErrorCode.UnexpectedCall, operation, message);
}
