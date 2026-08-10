namespace AtomiCloud.DotnetBase.UnitTest.Meta;

/// <summary>Every call fails, so no happy-path parity case can pass.</summary>
internal sealed class AlwaysFailingEmitter : ITraceEmitter
{
    private static TraceError Error => TraceErrors.Io("sabotage", "always fails");

    public Result<Unit, TraceError> Emit(TraceRecord record) => Error.With("span", record?.Name ?? "<null>");

    public Result<Unit, TraceError> Flush() => Error;
}

/// <summary>Every call succeeds vacuously, so no rejection case can pass.</summary>
internal sealed class AlwaysSucceedingEmitter : ITraceEmitter
{
    /// <summary>The span names it was handed, proving it really saw them and still passed.</summary>
    public List<string> Seen { get; } = [];

    public Result<Unit, TraceError> Emit(TraceRecord record)
    {
        Seen.Add(record?.Name ?? "<null>");
        return Result.Ok<Unit, TraceError>(default);
    }

    public Result<Unit, TraceError> Flush() => Result.Ok<Unit, TraceError>(default);
}

/// <summary>Records are accepted but dropped, so no capture case can pass.</summary>
internal sealed class ForgetfulEmitter : ITraceEmitter
{
    public int Emitted { get; private set; }

    public Result<Unit, TraceError> Emit(TraceRecord record)
    {
        Emitted++;
        return Result.Ok<Unit, TraceError>(default);
    }

    public Result<Unit, TraceError> Flush() => Result.Ok<Unit, TraceError>(default);
}

/// <summary>
/// Proves the parity expectations have teeth. If a saboteur could satisfy them, the
/// suite would be certifying nothing — so each saboteur is shown to violate exactly
/// the expectation its defect targets.
/// </summary>
public class SaboteurTests
{
    private static TraceRecord Record() => TraceRecord.Create("demo.request").Should().BeOk().Which;

    [Fact]
    public void AnAlwaysFailingEmitter_CannotSatisfyTheAcceptanceExpectation()
    {
        var emitter = new AlwaysFailingEmitter();

        emitter.Emit(Record()).Should().BeTraceErr(TraceErrorCode.Io);
        emitter.Flush().Should().BeTraceErr(TraceErrorCode.Io);
        FluentActions.Invoking(() => emitter.Emit(Record()).Should().BeOk()).Should().Throw<Exception>();
    }

    [Fact]
    public void AnAlwaysSucceedingEmitter_CannotSatisfyTheRejectionExpectation()
    {
        var emitter = new AlwaysSucceedingEmitter();

        emitter.Emit(null!).Should().BeOk();
        FluentActions
            .Invoking(() => emitter.Emit(null!).Should().BeTraceErr(TraceErrorCode.InvalidInput))
            .Should().Throw<Exception>();
        emitter.Seen.Should().AllBe("<null>");
    }

    [Fact]
    public void AForgetfulEmitter_CannotSatisfyTheCaptureExpectation()
    {
        var emitter = new ForgetfulEmitter();

        emitter.Emit(Record()).Should().BeOk();

        emitter.Emitted.Should().Be(1);
        FluentActions
            .Invoking(() => new InMemoryTraceEmitter().Should().HaveEmitted("demo.request"))
            .Should().Throw<Exception>();
    }

    [Fact]
    public void TheRealEmittersSatisfyBothExpectationsTheSaboteursBreak()
    {
        var emitter = new InMemoryTraceEmitter();

        emitter.Emit(Record()).Should().BeOk();
        emitter.Emit(null!).Should().BeTraceErr(TraceErrorCode.InvalidInput);
        emitter.Should().HaveEmitted("demo.request");
    }
}
