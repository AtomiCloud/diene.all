namespace AtomiCloud.DotnetBase.UnitTest.Tracing;

public class TraceErrorTests
{
    [Fact]
    public void Construct_CopiesDetailsIntoASortedMap()
    {
        var error = new TraceError(
            TraceErrorCode.Io,
            "emit",
            "exporter refused",
            [new("zulu", "z"), new("alpha", "a")]);

        error.Code.Should().Be(TraceErrorCode.Io);
        error.Operation.Should().Be("emit");
        error.Message.Should().Be("exporter refused");
        error.Details.Keys.Should().Equal("alpha", "zulu");
        error.ToString().Should().Be("io/emit: exporter refused");
    }

    [Fact]
    public void Construct_DefaultsToNoDetails() =>
        new TraceError(TraceErrorCode.Io, "emit", "failed").Details.Should().BeEmpty();

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public void Construct_RejectsABlankOperation(string? operation) =>
        FluentActions.Invoking(() => new TraceError(TraceErrorCode.Io, operation!, "failed"))
            .Should().Throw<ArgumentException>();

    [Fact]
    public void Construct_RejectsANullMessage() =>
        FluentActions.Invoking(() => new TraceError(TraceErrorCode.Io, "emit", null!))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void Construct_AcceptsAnEmptyMessage() =>
        new TraceError(TraceErrorCode.Io, "emit", "").Message.Should().BeEmpty();

    [Fact]
    public void With_ReturnsACopyAndLeavesTheOriginalAlone()
    {
        var original = TraceErrors.Io("emit", "failed");
        var annotated = original.With("span", "demo");

        annotated.Should().NotBeSameAs(original);
        annotated.Details["span"].Should().Be("demo");
        original.Details.Should().BeEmpty();
        annotated.Code.Should().Be(original.Code);
        annotated.Operation.Should().Be(original.Operation);
        annotated.Message.Should().Be(original.Message);
    }

    [Fact]
    public void With_OverwritesARepeatedKey() =>
        TraceErrors.Io("emit", "failed").With("k", "1").With("k", "2").Details["k"].Should().Be("2");

    [Theory]
    [InlineData(null)]
    [InlineData(" ")]
    public void With_RejectsABlankKey(string? key) =>
        FluentActions.Invoking(() => TraceErrors.Io("emit", "failed").With(key!, "v"))
            .Should().Throw<ArgumentException>();

    [Fact]
    public void With_RejectsANullValue() =>
        FluentActions.Invoking(() => TraceErrors.Io("emit", "failed").With("k", null!))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void Equality_IsByContent()
    {
        var left = TraceErrors.Io("emit", "failed").With("k", "v");
        var right = TraceErrors.Io("emit", "failed").With("k", "v");

        left.Equals(right).Should().BeTrue();
        left.Equals((object)right).Should().BeTrue();
        left.GetHashCode().Should().Be(right.GetHashCode());
        (left == right).Should().BeTrue();
        (left != right).Should().BeFalse();
    }

    [Fact]
    public void Equality_IsFalseOnAnyDifferingComponent()
    {
        var subject = TraceErrors.Io("emit", "failed").With("k", "v");

        subject.Equals(TraceErrors.Unavailable("emit", "failed").With("k", "v")).Should().BeFalse();
        subject.Equals(TraceErrors.Io("flush", "failed").With("k", "v")).Should().BeFalse();
        subject.Equals(TraceErrors.Io("emit", "other").With("k", "v")).Should().BeFalse();
        subject.Equals(TraceErrors.Io("emit", "failed")).Should().BeFalse();
        subject.Equals(TraceErrors.Io("emit", "failed").With("k", "other")).Should().BeFalse();
        subject.Equals((TraceError?)null).Should().BeFalse();
        subject!.Equals((object?)"not an error").Should().BeFalse();
    }

    [Fact]
    public void Operators_HandleNullOnEitherSide()
    {
        TraceError? none = null;
        var some = TraceErrors.Io("emit", "failed");

        (none == null).Should().BeTrue();
        (none != null).Should().BeFalse();
        (none == some).Should().BeFalse();
        (some == none).Should().BeFalse();
        (some != none).Should().BeTrue();
    }

    [Fact]
    public void Catalog_MapsEachFactoryToItsCode()
    {
        TraceErrors.InvalidInput("emit", "m").Code.Should().Be(TraceErrorCode.InvalidInput);
        TraceErrors.Io("emit", "m").Code.Should().Be(TraceErrorCode.Io);
        TraceErrors.Unavailable("emit", "m").Code.Should().Be(TraceErrorCode.Unavailable);
        TraceErrors.UnexpectedCall("flush", "m").Code.Should().Be(TraceErrorCode.UnexpectedCall);
    }
}

public class TraceWireTests
{
    [Theory]
    [InlineData(TraceStatus.Unset, "unset")]
    [InlineData(TraceStatus.Ok, "ok")]
    [InlineData(TraceStatus.Error, "error")]
    public void Name_MapsEveryStatus(TraceStatus status, string wire) => TraceWire.Name(status).Should().Be(wire);

    [Theory]
    [InlineData(TraceErrorCode.InvalidInput, "invalid-input")]
    [InlineData(TraceErrorCode.Io, "io")]
    [InlineData(TraceErrorCode.Unavailable, "unavailable")]
    [InlineData(TraceErrorCode.UnexpectedCall, "unexpected-call")]
    public void Name_MapsEveryErrorCode(TraceErrorCode code, string wire) => TraceWire.Name(code).Should().Be(wire);

    [Fact]
    public void Name_RejectsAnUndefinedStatus() =>
        FluentActions.Invoking(() => TraceWire.Name((TraceStatus)42))
            .Should().Throw<ArgumentOutOfRangeException>();

    [Fact]
    public void Name_RejectsAnUndefinedErrorCode() =>
        FluentActions.Invoking(() => TraceWire.Name((TraceErrorCode)42))
            .Should().Throw<ArgumentOutOfRangeException>();

    [Theory]
    [InlineData("unset", TraceStatus.Unset)]
    [InlineData("ok", TraceStatus.Ok)]
    [InlineData("error", TraceStatus.Error)]
    public void ParseStatus_RoundTripsEveryWireName(string wire, TraceStatus expected) =>
        TraceWire.ParseStatus(wire).Should().BeOk().Which.Should().Be(expected);

    [Theory]
    [InlineData("invalid-input", TraceErrorCode.InvalidInput)]
    [InlineData("io", TraceErrorCode.Io)]
    [InlineData("unavailable", TraceErrorCode.Unavailable)]
    [InlineData("unexpected-call", TraceErrorCode.UnexpectedCall)]
    public void ParseErrorCode_RoundTripsEveryWireName(string wire, TraceErrorCode expected) =>
        TraceWire.ParseErrorCode(wire).Should().BeOk().Which.Should().Be(expected);

    [Theory]
    [InlineData("OK")]
    [InlineData("sideways")]
    [InlineData("")]
    public void ParseStatus_RejectsAnythingElse(string wire) =>
        TraceWire.ParseStatus(wire).Should().BeErr().Which.Message.Should().Contain("status");

    [Theory]
    [InlineData("invalid_input")]
    [InlineData("nonsense")]
    public void ParseErrorCode_RejectsAnythingElse(string wire) =>
        TraceWire.ParseErrorCode(wire).Should().BeErr().Which.Message.Should().Contain("code");

    [Fact]
    public void ParseFailures_ReportTheParseOperation() =>
        TraceWire.ParseStatus("nope").Should().BeErr().Which.Operation.Should().Be("parse");
}
