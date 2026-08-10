namespace AtomiCloud.DotnetBase.UnitTest.Tracing;

public class TraceEventTests
{
    [Fact]
    public void Create_AcceptsANameAndSortsAttributes()
    {
        var recorded = TraceEvent
            .Create("cache.miss", [new("z", AttributeValue.Text("z")), new("a", AttributeValue.Text("a"))])
            .Should().BeOk().Which;

        recorded.Name.Should().Be("cache.miss");
        recorded.Attributes.Keys.Should().Equal("a", "z");
        recorded.ToString().Should().Be("cache.miss");
    }

    [Fact]
    public void Create_DefaultsToNoAttributes() =>
        TraceEvent.Create("cache.miss").Should().BeOk().Which.Attributes.Should().BeEmpty();

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Create_RejectsABlankName(string? name) =>
        TraceEvent.Create(name).Should().BeErr().Which.Message.Should().Contain("must not be blank");

    [Fact]
    public void Create_PropagatesAnAttributeRejection() =>
        TraceEvent
            .Create("cache.miss", [new(" ", AttributeValue.Text("x"))])
            .Should().BeErr()
            .Which.Code.Should().Be(TraceErrorCode.InvalidInput);

    [Fact]
    public void Equality_IsByContent()
    {
        var left = TraceEvent.Create("e", [new("a", AttributeValue.Integer(1))]).Should().BeOk().Which;
        var right = TraceEvent.Create("e", [new("a", AttributeValue.Integer(1))]).Should().BeOk().Which;
        var other = TraceEvent.Create("e", [new("a", AttributeValue.Integer(2))]).Should().BeOk().Which;
        var renamed = TraceEvent.Create("f", [new("a", AttributeValue.Integer(1))]).Should().BeOk().Which;

        left.Equals(right).Should().BeTrue();
        left.Equals((object)right).Should().BeTrue();
        left.GetHashCode().Should().Be(right.GetHashCode());
        left.Equals(other).Should().BeFalse();
        left.Equals(renamed).Should().BeFalse();
        left.Equals((TraceEvent?)null).Should().BeFalse();
        left!.Equals((object?)"not an event").Should().BeFalse();
    }
}

public class TraceRecordTests
{
    private static TraceEvent Recorded { get; } = TraceEvent.Create("step").Should().BeOk().Which;

    [Fact]
    public void Create_AcceptsAFullyPopulatedSpan()
    {
        var record = TraceRecord
            .Create(
                "demo.request",
                [new("route", AttributeValue.Text("/v1"))],
                [Recorded],
                TraceStatus.Ok,
                "served")
            .Should().BeOk().Which;

        record.Name.Should().Be("demo.request");
        record.Attributes.Should().ContainKey("route");
        record.Events.Should().Equal(Recorded);
        record.Status.Should().Be(TraceStatus.Ok);
        record.StatusMessage.Should().BeSome().Which.Should().Be("served");
        record.ToString().Should().Be("demo.request ok");
    }

    [Fact]
    public void Create_DefaultsToAnUnsetSpanWithNothingAttached()
    {
        var record = TraceRecord.Create("demo.request").Should().BeOk().Which;

        record.Attributes.Should().BeEmpty();
        record.Events.Should().BeEmpty();
        record.Status.Should().Be(TraceStatus.Unset);
        record.StatusMessage.Should().BeNone();
        record.ToString().Should().Be("demo.request unset");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public void Create_RejectsABlankName(string? name) =>
        TraceRecord.Create(name).Should().BeErr().Which.Message.Should().Contain("Trace name");

    [Fact]
    public void Create_RejectsAnUndefinedStatus() =>
        TraceRecord
            .Create("demo.request", status: (TraceStatus)42)
            .Should().BeErr()
            .Which.Message.Should().Contain("status is invalid");

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Create_RejectsABlankStatusMessage(string message) =>
        TraceRecord
            .Create("demo.request", statusMessage: message)
            .Should().BeErr()
            .Which.Message.Should().Contain("status message");

    [Fact]
    public void Create_RejectsANullEventInTheSequence() =>
        TraceRecord
            .Create("demo.request", events: [null!])
            .Should().BeErr()
            .Which.Message.Should().Contain("must not be null");

    [Fact]
    public void Create_PropagatesAnAttributeRejection() =>
        TraceRecord
            .Create("demo.request", [new(" ", AttributeValue.Text("x"))])
            .Should().BeErr()
            .Which.Code.Should().Be(TraceErrorCode.InvalidInput);

    [Fact]
    public void Create_CopiesTheEventSequenceSoLaterMutationCannotLeakIn()
    {
        var events = new List<TraceEvent> { Recorded };
        var record = TraceRecord.Create("demo.request", events: events).Should().BeOk().Which;
        events.Add(TraceEvent.Create("late").Should().BeOk().Which);
        record.Events.Should().HaveCount(1);
    }

    [Fact]
    public void Equality_IsByContent()
    {
        var left = TraceRecord.Create("s", [new("a", AttributeValue.Integer(1))], [Recorded], TraceStatus.Ok, "m")
            .Should().BeOk().Which;
        var right = TraceRecord.Create("s", [new("a", AttributeValue.Integer(1))], [Recorded], TraceStatus.Ok, "m")
            .Should().BeOk().Which;

        left.Equals(right).Should().BeTrue();
        left.Equals((object)right).Should().BeTrue();
        left.GetHashCode().Should().Be(right.GetHashCode());
        left.Equals((TraceRecord?)null).Should().BeFalse();
        left!.Equals((object?)"not a span").Should().BeFalse();
    }

    [Fact]
    public void Equality_IsFalseOnAnyDifferingComponent()
    {
        var subject = TraceRecord.Create("s", [new("a", AttributeValue.Integer(1))], [Recorded], TraceStatus.Ok, "m")
            .Should().BeOk().Which;

        subject.Equals(TraceRecord.Create("other", [new("a", AttributeValue.Integer(1))], [Recorded], TraceStatus.Ok, "m")
            .Should().BeOk().Which).Should().BeFalse();
        subject.Equals(TraceRecord.Create("s", [new("a", AttributeValue.Integer(2))], [Recorded], TraceStatus.Ok, "m")
            .Should().BeOk().Which).Should().BeFalse();
        subject.Equals(TraceRecord.Create("s", [new("a", AttributeValue.Integer(1))], [], TraceStatus.Ok, "m")
            .Should().BeOk().Which).Should().BeFalse();
        subject.Equals(TraceRecord.Create("s", [new("a", AttributeValue.Integer(1))], [Recorded], TraceStatus.Error, "m")
            .Should().BeOk().Which).Should().BeFalse();
        subject.Equals(TraceRecord.Create("s", [new("a", AttributeValue.Integer(1))], [Recorded], TraceStatus.Ok, "other")
            .Should().BeOk().Which).Should().BeFalse();
    }
}
