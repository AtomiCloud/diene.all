namespace AtomiCloud.DotnetBase.UnitTest.Meta;

/// <summary>
/// Assert-the-asserter. A matcher that cannot fail is worse than no matcher at all:
/// it makes a red suite look green. Every helper here is proven to pass on a
/// known-good case AND to throw on a known-bad one.
/// </summary>
public class AssertTheAsserterTests
{
    private static TraceRecord Record(
        string name = "demo.request",
        TraceStatus status = TraceStatus.Ok) =>
        TraceRecord
            .Create(
                name,
                [new("route", AttributeValue.Text("/v1"))],
                [TraceEvent.Create("cache.miss").Should().BeOk().Which],
                status)
            .Should().BeOk().Which;

    private static InMemoryTraceEmitter Emitted(params TraceRecord[] records)
    {
        var emitter = new InMemoryTraceEmitter();
        foreach (var record in records) emitter.Emit(record).Should().BeOk();
        return emitter;
    }

    [Fact]
    public void HaveEmitted_PassesOnAMatchAndFailsOnAMiss()
    {
        var emitter = Emitted(Record());

        emitter.Should().HaveEmitted("demo.request").Which.Name.Should().Be("demo.request");
        FluentActions.Invoking(() => emitter.Should().HaveEmitted("other")).Should().Throw<Exception>();
    }

    [Fact]
    public void HaveEmitted_FailsOnAnEmptyEmitterAndSaysSo() =>
        FluentActions.Invoking(() => new InMemoryTraceEmitter().Should().HaveEmitted("demo.request"))
            .Should().Throw<Exception>()
            .WithMessage("*no spans*");

    [Fact]
    public void NotHaveEmitted_PassesWhenAbsentAndFailsWhenPresent()
    {
        var emitter = Emitted(Record());

        emitter.Should().NotHaveEmitted("other");
        FluentActions.Invoking(() => emitter.Should().NotHaveEmitted("demo.request")).Should().Throw<Exception>();
    }

    [Fact]
    public void HaveEmittedExactly_PassesOnTheExactSequenceAndFailsOnAnyDeviation()
    {
        var emitter = Emitted(Record("first"), Record("second"));

        emitter.Should().HaveEmittedExactly(["first", "second"]);
        FluentActions.Invoking(() => emitter.Should().HaveEmittedExactly(["second", "first"]))
            .Should().Throw<Exception>();
        FluentActions.Invoking(() => emitter.Should().HaveEmittedExactly(["first"]))
            .Should().Throw<Exception>();
        FluentActions.Invoking(() => emitter.Should().HaveEmittedExactly(["first", "second", "third"]))
            .Should().Throw<Exception>();
    }

    [Fact]
    public void HaveEmittedExactly_RejectsANullSequence() =>
        FluentActions.Invoking(() => Emitted(Record()).Should().HaveEmittedExactly(null!))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void HaveFlushed_PassesOnTheExactCountAndFailsOnAnyOther()
    {
        var emitter = new InMemoryTraceEmitter();
        emitter.Flush().Should().BeOk();

        emitter.Should().HaveFlushed(1);
        FluentActions.Invoking(() => emitter.Should().HaveFlushed(0)).Should().Throw<Exception>();
        FluentActions.Invoking(() => emitter.Should().HaveFlushed(2)).Should().Throw<Exception>();
    }

    [Fact]
    public void HaveAttribute_PassesOnAMatchAndFailsOnAWrongValueOrMissingKey()
    {
        var record = Record();

        record.Should().HaveAttribute("route", AttributeValue.Text("/v1"));
        FluentActions.Invoking(() => record.Should().HaveAttribute("route", AttributeValue.Text("/v2")))
            .Should().Throw<Exception>();
        FluentActions.Invoking(() => record.Should().HaveAttribute("missing", AttributeValue.Text("/v1")))
            .Should().Throw<Exception>()
            .WithMessage("*no 'missing'*");
    }

    [Fact]
    public void HaveEvent_PassesOnAMatchAndFailsOnAMiss()
    {
        var record = Record();

        record.Should().HaveEvent("cache.miss").Which.Name.Should().Be("cache.miss");
        FluentActions.Invoking(() => record.Should().HaveEvent("other")).Should().Throw<Exception>();
    }

    [Fact]
    public void HaveEvent_FailsOnAnEventlessSpanAndSaysSo() =>
        FluentActions
            .Invoking(() => TraceRecord.Create("bare").Should().BeOk().Which.Should().HaveEvent("cache.miss"))
            .Should().Throw<Exception>()
            .WithMessage("*no events*");

    [Fact]
    public void HaveStatus_PassesOnAMatchAndFailsOnAnyOtherOutcome()
    {
        var record = Record(status: TraceStatus.Error);

        record.Should().HaveStatus(TraceStatus.Error);
        FluentActions.Invoking(() => record.Should().HaveStatus(TraceStatus.Ok)).Should().Throw<Exception>();
        FluentActions.Invoking(() => record.Should().HaveStatus(TraceStatus.Unset)).Should().Throw<Exception>();
    }

    [Fact]
    public void BeTraceErr_PassesOnTheExactCodeAndFailsOnAnother()
    {
        var failure = Result.Err<Unit, TraceError>(TraceErrors.Io("emit", "exporter refused"));

        failure.Should().BeTraceErr(TraceErrorCode.Io).Which.Message.Should().Be("exporter refused");
        FluentActions.Invoking(() => failure.Should().BeTraceErr(TraceErrorCode.InvalidInput))
            .Should().Throw<Exception>();
    }

    [Fact]
    public void BeTraceErr_FailsOnASuccessfulResult() =>
        FluentActions
            .Invoking(() => Result.Ok<Unit, TraceError>(default).Should().BeTraceErr(TraceErrorCode.Io))
            .Should().Throw<Exception>();

    [Fact]
    public void BeTraceErr_RejectsNullAssertions() =>
        FluentActions
            .Invoking(() => TraceAssertionExtensions.BeTraceErr<Unit>(null!, TraceErrorCode.Io))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void Should_ReturnsAChainRootedOnTheSubjectItWasGiven()
    {
        var emitter = Emitted(Record());
        var record = Record();

        ReferenceEquals(emitter.Should().Subject, emitter).Should().BeTrue();
        ReferenceEquals(record.Should().Subject, record).Should().BeTrue();
    }
}
