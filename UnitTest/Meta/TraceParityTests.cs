using System.Diagnostics;

namespace AtomiCloud.DotnetBase.UnitTest.Meta;

/// <summary>
/// Contract parity: ONE behavioral suite run against BOTH the real
/// <see cref="ActivityTraceEmitter" /> and the <see cref="InMemoryTraceEmitter" />
/// consumers substitute for it. A mock that diverges from the real emitter is a
/// broken test double, so the suite is the guarantee that substituting is safe.
/// This is the twin of the bun sibling's <c>tests/meta/parity.test.ts</c>.
/// </summary>
public class TraceParityTests
{
    /// <summary>The emitters under parity, each with the capture its assertions read.</summary>
    public static TheoryData<string> Emitters => new("activity", "in-memory");

    private static TraceRecord Record(
        string name,
        TraceStatus status = TraceStatus.Unset,
        params KeyValuePair<string, AttributeValue>[] attributes) =>
        TraceRecord.Create(name, attributes, status: status).Should().BeOk().Which;

    private static (ITraceEmitter Emitter, Func<IReadOnlyList<string>> Names, IDisposable Scope) Subject(string kind)
    {
        if (kind == "in-memory")
        {
            var emitter = new InMemoryTraceEmitter();
            return (emitter, () => [.. emitter.Records.Select(record => record.Name)], new Nothing());
        }

        var instrumentation = new Instrumentation(new AppIdentity("l", "p", $"parity-{Guid.NewGuid():N}", "m", "1.0.0"));
        var stopped = new List<string>();
        var listener = new ActivityListener
        {
            ShouldListenTo = source => string.Equals(
                source.Name,
                instrumentation.ActivitySource.Name,
                StringComparison.Ordinal),
            Sample = (ref _) => ActivitySamplingResult.AllDataAndRecorded,
            ActivityStopped = activity => stopped.Add(activity.DisplayName),
        };
        ActivitySource.AddActivityListener(listener);
        return (
            new ActivityTraceEmitter(instrumentation),
            () => stopped,
            new Both(listener, instrumentation));
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_AcceptsAValidSpan(string kind)
    {
        var (emitter, names, scope) = Subject(kind);
        using (scope)
        {
            emitter.Emit(Record("demo.request")).Should().BeOk();
            names().Should().Equal("demo.request");
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_PreservesEmitOrder(string kind)
    {
        var (emitter, names, scope) = Subject(kind);
        using (scope)
        {
            emitter.Emit(Record("first")).Should().BeOk();
            emitter.Emit(Record("second")).Should().BeOk();
            emitter.Emit(Record("third")).Should().BeOk();
            names().Should().Equal("first", "second", "third");
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_RejectsANullRecordAsInvalidInput(string kind)
    {
        var (emitter, _, scope) = Subject(kind);
        using (scope)
        {
            emitter.Emit(null!).Should().BeTraceErr(TraceErrorCode.InvalidInput);
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_AcceptsEveryStatus(string kind)
    {
        var (emitter, names, scope) = Subject(kind);
        using (scope)
        {
            foreach (var status in Enum.GetValues<TraceStatus>())
            {
                emitter.Emit(Record($"span.{status}", status)).Should().BeOk();
            }

            names().Should().HaveCount(3);
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_AcceptsEveryAttributeKind(string kind)
    {
        var (emitter, names, scope) = Subject(kind);
        using (scope)
        {
            emitter
                .Emit(Record(
                    "rich",
                    TraceStatus.Ok,
                    new("text", AttributeValue.Text("value")),
                    new("integer", AttributeValue.Integer(7)),
                    new("real", AttributeValue.Real(1.5)),
                    new("flag", AttributeValue.Flag(true)),
                    new("instant", AttributeValue.Instant(DateTimeOffset.UnixEpoch)),
                    new("duration", AttributeValue.Duration(TimeSpan.FromSeconds(30)))))
                .Should().BeOk();
            names().Should().Equal("rich");
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_AcceptsASpanCarryingNothingButAName(string kind)
    {
        var (emitter, names, scope) = Subject(kind);
        using (scope)
        {
            emitter.Emit(Record("bare")).Should().BeOk();
            names().Should().Equal("bare");
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_FlushesSuccessfullyAndRepeatedly(string kind)
    {
        var (emitter, _, scope) = Subject(kind);
        using (scope)
        {
            emitter.Flush().Should().BeOk();
            emitter.Flush().Should().BeOk();
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_KeepsWorkingAfterAFlush(string kind)
    {
        var (emitter, names, scope) = Subject(kind);
        using (scope)
        {
            emitter.Emit(Record("before")).Should().BeOk();
            emitter.Flush().Should().BeOk();
            emitter.Emit(Record("after")).Should().BeOk();
            names().Should().Equal("before", "after");
        }
    }

    private sealed class Nothing : IDisposable
    {
        public void Dispose()
        {
        }
    }

    private sealed class Both(IDisposable first, IDisposable second) : IDisposable
    {
        public void Dispose()
        {
            first.Dispose();
            second.Dispose();
        }
    }
}
