using FluentAssertions;
using FluentAssertions.Execution;

namespace AtomiCloud.Diene.Otel.TestHelper;

/// <summary>
/// FluentAssertions steps over captured spans and trace-seam results. These EXTEND
/// the published <c>AtomiCloud.Diene.Result.TestHelper</c> assertions rather than
/// duplicating them, so a consumer keeps one <c>Should()</c> entry point.
/// </summary>
public static class TraceAssertionExtensions
{
    /// <summary>Starts an assertion chain over a recording trace emitter.</summary>
    public static TraceEmitterAssertions Should(this InMemoryTraceEmitter subject) => new(subject);

    /// <summary>Starts an assertion chain over one captured span.</summary>
    public static TraceRecordAssertions Should(this TraceRecord subject) => new(subject);

    /// <summary>Asserts the Result failed with a specific trace failure code.</summary>
    public static AndWhichConstraint<
        AtomiCloud.Diene.Results.TestHelper.ResultAssertions<T, TraceError>,
        TraceError> BeTraceErr<T>(
        this AtomiCloud.Diene.Results.TestHelper.ResultAssertions<T, TraceError> assertions,
        TraceErrorCode code,
        string because = "",
        params object[] becauseArgs)
    {
        ArgumentNullException.ThrowIfNull(assertions);
        var error = assertions.BeErr(because, becauseArgs).Which;
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(error.Code == code)
            .FailWith(
                "Expected the result to fail with {0}{reason}, but found {1}.",
                TraceWire.Name(code),
                TraceWire.Name(error.Code));
        return new AndWhichConstraint<
            AtomiCloud.Diene.Results.TestHelper.ResultAssertions<T, TraceError>,
            TraceError>(assertions, error);
    }
}

/// <summary>Assertions over the spans a trace emitter captured.</summary>
/// <param name="subject">The emitter under assertion.</param>
public sealed class TraceEmitterAssertions(InMemoryTraceEmitter subject)
{
    /// <summary>The emitter under assertion.</summary>
    public InMemoryTraceEmitter Subject { get; } = subject;

    /// <summary>Asserts one span with an exact name was accepted.</summary>
    public AndWhichConstraint<TraceEmitterAssertions, TraceRecord> HaveEmitted(
        string name,
        string because = "",
        params object[] becauseArgs)
    {
        var match = Subject.Records.FirstOrDefault(record =>
            string.Equals(record.Name, name, StringComparison.Ordinal));
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(match is not null)
            .FailWith(
                "Expected the trace emitter to have emitted {0}{reason}, but found {1}.",
                name,
                Names(Subject.Records));
        return new AndWhichConstraint<TraceEmitterAssertions, TraceRecord>(this, match!);
    }

    /// <summary>Asserts no span with the name was accepted.</summary>
    public AndConstraint<TraceEmitterAssertions> NotHaveEmitted(
        string name,
        string because = "",
        params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(!Subject.Records.Any(record =>
                string.Equals(record.Name, name, StringComparison.Ordinal)))
            .FailWith("Expected the trace emitter not to have emitted {0}{reason}, but it did.", name);
        return new AndConstraint<TraceEmitterAssertions>(this);
    }

    /// <summary>Asserts the accepted spans are exactly these names, in order.</summary>
    public AndConstraint<TraceEmitterAssertions> HaveEmittedExactly(
        IEnumerable<string> names,
        string because = "",
        params object[] becauseArgs)
    {
        ArgumentNullException.ThrowIfNull(names);
        var expected = names.ToArray();
        var actual = Subject.Records.Select(record => record.Name).ToArray();
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(actual.SequenceEqual(expected, StringComparer.Ordinal))
            .FailWith(
                "Expected the trace emitter to have emitted exactly {0}{reason}, but found {1}.",
                string.Join(", ", expected),
                string.Join(", ", actual));
        return new AndConstraint<TraceEmitterAssertions>(this);
    }

    /// <summary>Asserts the seam was flushed an exact number of times.</summary>
    public AndConstraint<TraceEmitterAssertions> HaveFlushed(
        int times,
        string because = "",
        params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.Flushes == times)
            .FailWith(
                "Expected the trace emitter to have flushed {0} time(s){reason}, but found {1}.",
                times,
                Subject.Flushes);
        return new AndConstraint<TraceEmitterAssertions>(this);
    }

    private static string Names(IReadOnlyList<TraceRecord> records) =>
        records.Count == 0 ? "no spans" : string.Join(", ", records.Select(record => record.Name));
}

/// <summary>Assertions over one captured span.</summary>
/// <param name="subject">The span under assertion.</param>
public sealed class TraceRecordAssertions(TraceRecord subject)
{
    /// <summary>The span under assertion.</summary>
    public TraceRecord Subject { get; } = subject;

    /// <summary>Asserts the span carries an attribute with an exact wire value.</summary>
    public AndConstraint<TraceRecordAssertions> HaveAttribute(
        string key,
        AttributeValue value,
        string because = "",
        params object[] becauseArgs)
    {
        var found = Subject.Attributes.TryGetValue(key, out var actual) && actual == value;
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(found)
            .FailWith(
                "Expected the span to carry {0}{reason}, but found {1}.",
                $"{key}={value}",
                Subject.Attributes.TryGetValue(key, out var other) ? $"{key}={other}" : $"no '{key}'");
        return new AndConstraint<TraceRecordAssertions>(this);
    }

    /// <summary>Asserts the span recorded an event with an exact name.</summary>
    public AndWhichConstraint<TraceRecordAssertions, TraceEvent> HaveEvent(
        string name,
        string because = "",
        params object[] becauseArgs)
    {
        var match = Subject.Events.FirstOrDefault(recorded =>
            string.Equals(recorded.Name, name, StringComparison.Ordinal));
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(match is not null)
            .FailWith(
                "Expected the span to have recorded event {0}{reason}, but found {1}.",
                name,
                Subject.Events.Count == 0
                    ? "no events"
                    : string.Join(", ", Subject.Events.Select(recorded => recorded.Name)));
        return new AndWhichConstraint<TraceRecordAssertions, TraceEvent>(this, match!);
    }

    /// <summary>Asserts the span reported an exact outcome.</summary>
    public AndConstraint<TraceRecordAssertions> HaveStatus(
        TraceStatus status,
        string because = "",
        params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.Status == status)
            .FailWith(
                "Expected the span to report {0}{reason}, but found {1}.",
                TraceWire.Name(status),
                TraceWire.Name(Subject.Status));
        return new AndConstraint<TraceRecordAssertions>(this);
    }
}
