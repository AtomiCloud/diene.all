namespace AtomiCloud.DotnetBase.UnitTest.Meta;

public class InMemoryTraceEmitterTests
{
    private static TraceRecord Record(string name = "demo.request") =>
        TraceRecord
            .Create(name, [new("route", AttributeValue.Text("/v1"))], status: TraceStatus.Ok, statusMessage: "served")
            .Should().BeOk().Which;

    [Fact]
    public void Emit_CapturesTheSpanAndTheCall()
    {
        var emitter = new InMemoryTraceEmitter();
        var record = Record();

        emitter.Emit(record).Should().BeOk();

        emitter.Records.Should().Equal(record);
        emitter.Calls.Should().ContainSingle().Which.Should()
            .Be(new TraceCall(0, TraceCallKind.Emit, Option.Some(record)));
    }

    [Fact]
    public void Calls_AreSequencedAcrossBothMethods()
    {
        var emitter = new InMemoryTraceEmitter();

        emitter.Emit(Record("first")).Should().BeOk();
        emitter.Flush().Should().BeOk();
        emitter.Emit(Record("second")).Should().BeOk();

        emitter.Calls.Select(call => call.Sequence).Should().Equal(0, 1, 2);
        emitter.Calls.Select(call => call.Kind).Should()
            .Equal(TraceCallKind.Emit, TraceCallKind.Flush, TraceCallKind.Emit);
    }

    [Fact]
    public void Flush_CarriesNoSpanAndIsCounted()
    {
        var emitter = new InMemoryTraceEmitter();

        emitter.Flush().Should().BeOk();
        emitter.Flush().Should().BeOk();

        emitter.Flushes.Should().Be(2);
        emitter.Calls.Should().AllSatisfy(call => call.Record.Should().BeNone());
        emitter.Records.Should().BeEmpty();
    }

    [Fact]
    public void FailNext_FailsTheNextEmitAndRecordsTheAttemptWithoutAcceptingIt()
    {
        var emitter = new InMemoryTraceEmitter();
        var error = TraceErrors.Io("emit", "exporter refused");

        emitter.FailNext(error);
        emitter.Emit(Record()).Should().BeErr().Which.Should().Be(error);

        emitter.Records.Should().BeEmpty();
        emitter.Calls.Should().ContainSingle().Which.Kind.Should().Be(TraceCallKind.Emit);
    }

    [Fact]
    public void FailNext_AppliesToAFlushToo()
    {
        var emitter = new InMemoryTraceEmitter();
        var error = TraceErrors.Unavailable("flush", "shutting down");

        emitter.FailNext(error);
        emitter.Flush().Should().BeErr().Which.Should().Be(error);
        emitter.Flush().Should().BeOk();
    }

    [Fact]
    public void FailNext_IsConsumedOnceAndQueuesInOrder()
    {
        var emitter = new InMemoryTraceEmitter();
        var first = TraceErrors.Io("emit", "first");
        var second = TraceErrors.Unavailable("emit", "second");

        emitter.FailNext(first);
        emitter.FailNext(second);

        emitter.Emit(Record()).Should().BeErr().Which.Should().Be(first);
        emitter.Emit(Record()).Should().BeErr().Which.Should().Be(second);
        emitter.Emit(Record()).Should().BeOk();
        emitter.Records.Should().HaveCount(1);
    }

    [Fact]
    public void FailNext_RejectsANullError() =>
        FluentActions.Invoking(() => new InMemoryTraceEmitter().FailNext(null!))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void Emit_RejectsANullRecordWithoutRecordingACall()
    {
        var emitter = new InMemoryTraceEmitter();

        emitter.Emit(null!).Should().BeErr().Which.Code.Should().Be(TraceErrorCode.InvalidInput);

        emitter.Calls.Should().BeEmpty();
    }

    [Fact]
    public void Named_FiltersTheAcceptedSpansByName()
    {
        var emitter = new InMemoryTraceEmitter();
        emitter.Emit(Record("a")).Should().BeOk();
        emitter.Emit(Record("b")).Should().BeOk();
        emitter.Emit(Record("a")).Should().BeOk();

        emitter.Named("a").Should().HaveCount(2);
        emitter.Named("b").Should().HaveCount(1);
        emitter.Named("missing").Should().BeEmpty();
    }

    [Fact]
    public void Named_RejectsANullName() =>
        FluentActions.Invoking(() => new InMemoryTraceEmitter().Named(null!))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void Clear_DiscardsSpansCallsAndQueuedFailures()
    {
        var emitter = new InMemoryTraceEmitter();
        emitter.Emit(Record()).Should().BeOk();
        emitter.Flush().Should().BeOk();
        emitter.FailNext(TraceErrors.Io("emit", "queued"));

        emitter.Clear();

        emitter.Records.Should().BeEmpty();
        emitter.Calls.Should().BeEmpty();
        emitter.Flushes.Should().Be(0);
        emitter.Emit(Record()).Should().BeOk();
    }

    [Fact]
    public void Snapshots_AreCopiesSoALaterCallCannotMutateAnEarlierReading()
    {
        var emitter = new InMemoryTraceEmitter();
        emitter.Emit(Record()).Should().BeOk();

        var records = emitter.Records;
        var calls = emitter.Calls;
        emitter.Emit(Record("later")).Should().BeOk();

        records.Should().HaveCount(1);
        calls.Should().HaveCount(1);
    }

    [Fact]
    public void TraceCall_HasValueEquality()
    {
        var record = Record();
        var left = new TraceCall(0, TraceCallKind.Emit, Option.Some(record));

        left.Should().Be(new TraceCall(0, TraceCallKind.Emit, Option.Some(record)));
        left.Should().NotBe(new TraceCall(1, TraceCallKind.Emit, Option.Some(record)));
        left.Should().NotBe(new TraceCall(0, TraceCallKind.Flush, Option.Some(record)));
        left.GetHashCode().Should().Be(new TraceCall(0, TraceCallKind.Emit, Option.Some(record)).GetHashCode());
    }
}
