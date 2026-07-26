using System.Diagnostics;

namespace AtomiCloud.DotnetBase.UnitTest.Tracing;

/// <summary>Captures the activities an emitter produced, via a real ActivityListener.</summary>
internal sealed class ActivityCapture : IDisposable
{
    private readonly ActivityListener _listener;

    public ActivityCapture(string source)
    {
        _listener = new ActivityListener
        {
            ShouldListenTo = candidate => string.Equals(candidate.Name, source, StringComparison.Ordinal),
            Sample = (ref _) => ActivitySamplingResult.AllDataAndRecorded,
            ActivityStopped = Stopped.Add,
        };
        ActivitySource.AddActivityListener(_listener);
    }

    public List<Activity> Stopped { get; } = [];

    public void Dispose() => _listener.Dispose();
}

public class ActivityTraceEmitterTests : IDisposable
{
    private readonly Instrumentation _instrumentation = new(new AppIdentity("l", "p", "billing", "m", "1.0.0"));

    private static TraceRecord Record(
        TraceStatus status = TraceStatus.Ok,
        string? statusMessage = "served") =>
        TraceRecord
            .Create(
                "demo.request",
                [new("route", AttributeValue.Text("/v1")), new("attempt", AttributeValue.Integer(1))],
                [TraceEvent.Create("cache.miss", [new("key", AttributeValue.Text("k"))]).Should().BeOk().Which],
                status,
                statusMessage)
            .Should().BeOk().Which;

    public void Dispose()
    {
        _instrumentation.Dispose();
        GC.SuppressFinalize(this);
    }

    [Fact]
    public void Construct_RejectsANullInstrumentation() =>
        FluentActions.Invoking(() => new ActivityTraceEmitter(null!)).Should().Throw<ArgumentNullException>();

    [Fact]
    public void Emit_ProducesAnActivityCarryingTagsEventsAndStatus()
    {
        using var capture = new ActivityCapture(_instrumentation.ActivitySource.Name);

        new ActivityTraceEmitter(_instrumentation).Emit(Record()).Should().BeOk();

        var activity = capture.Stopped.Should().ContainSingle().Which;
        activity.DisplayName.Should().Be("demo.request");
        activity.GetTagItem("route").Should().Be("/v1");
        activity.GetTagItem("attempt").Should().Be("1");
        activity.Status.Should().Be(ActivityStatusCode.Ok);
        activity.Events.Should().ContainSingle().Which.Name.Should().Be("cache.miss");
        activity.Events.Single().Tags.Should().Contain(new KeyValuePair<string, object?>("key", "k"));
    }

    [Theory]
    [InlineData(TraceStatus.Unset, ActivityStatusCode.Unset)]
    [InlineData(TraceStatus.Ok, ActivityStatusCode.Ok)]
    [InlineData(TraceStatus.Error, ActivityStatusCode.Error)]
    public void Emit_MapsEveryStatus(TraceStatus status, ActivityStatusCode expected)
    {
        using var capture = new ActivityCapture(_instrumentation.ActivitySource.Name);

        new ActivityTraceEmitter(_instrumentation).Emit(Record(status)).Should().BeOk();

        capture.Stopped.Should().ContainSingle().Which.Status.Should().Be(expected);
    }

    [Fact]
    public void Emit_CarriesTheStatusMessageOnAFailedSpan()
    {
        using var capture = new ActivityCapture(_instrumentation.ActivitySource.Name);

        new ActivityTraceEmitter(_instrumentation)
            .Emit(Record(TraceStatus.Error, "upstream refused"))
            .Should().BeOk();

        // Activity only retains a description for the Error status; that is the case a
        // reader actually needs it for.
        capture.Stopped.Should().ContainSingle().Which.StatusDescription.Should().Be("upstream refused");
    }

    [Fact]
    public void Emit_LeavesTheDescriptionUnsetWhenTheSpanCarriesNoMessage()
    {
        using var capture = new ActivityCapture(_instrumentation.ActivitySource.Name);

        new ActivityTraceEmitter(_instrumentation).Emit(Record(statusMessage: null)).Should().BeOk();

        capture.Stopped.Should().ContainSingle().Which.StatusDescription.Should().BeNull();
    }

    [Fact]
    public void Emit_IsASuccessfulNoOpWhenNothingIsListening()
    {
        new ActivityTraceEmitter(_instrumentation).Emit(Record()).Should().BeOk();
    }

    [Fact]
    public void Emit_RejectsANullRecord() =>
        new ActivityTraceEmitter(_instrumentation)
            .Emit(null!)
            .Should().BeErr()
            .Which.Code.Should().Be(TraceErrorCode.InvalidInput);

    [Fact]
    public void Emit_AcceptsASpanCarryingNothingButAName()
    {
        using var capture = new ActivityCapture(_instrumentation.ActivitySource.Name);

        new ActivityTraceEmitter(_instrumentation)
            .Emit(TraceRecord.Create("bare").Should().BeOk().Which)
            .Should().BeOk();

        var activity = capture.Stopped.Should().ContainSingle().Which;
        activity.TagObjects.Should().BeEmpty();
        activity.Events.Should().BeEmpty();
    }

    [Fact]
    public void Flush_SucceedsBecauseTheSdkOwnsTheExportSchedule() =>
        new ActivityTraceEmitter(_instrumentation).Flush().Should().BeOk();
}
