namespace AtomiCloud.DotnetBase.UnitTest.Tracing;

public class TraceAttributesTests
{
    private static Dictionary<string, AttributeValue> Of(string key, AttributeValue value) =>
        new(StringComparer.Ordinal) { [key] = value };

    [Fact]
    public void Empty_IsAnEmptyOrdinalMap()
    {
        TraceAttributes.Empty.Should().BeEmpty();
        TraceAttributes.Equal(TraceAttributes.Empty, TraceAttributes.Empty).Should().BeTrue();
    }

    [Fact]
    public void Check_TreatsNullAsEmpty() =>
        TraceAttributes.Check(null, "emit").Should().BeOk().Which.Should().BeEmpty();

    [Fact]
    public void Check_SortsKeysSoOrderCannotAffectEquality()
    {
        var checked_ = TraceAttributes
            .Check(
                [
                    new("zulu", AttributeValue.Text("z")),
                    new("alpha", AttributeValue.Text("a")),
                    new("mike", AttributeValue.Text("m")),
                ],
                "emit")
            .Should().BeOk().Which;

        checked_.Keys.Should().Equal("alpha", "mike", "zulu");
    }

    [Fact]
    public void Check_KeepsTheLastValueForARepeatedKey() =>
        TraceAttributes
            .Check([new("key", AttributeValue.Integer(1)), new("key", AttributeValue.Integer(2))], "emit")
            .Should().BeOk()
            .Which["key"].Should().Be(AttributeValue.Integer(2));

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("\t")]
    public void Check_RejectsABlankKey(string key) =>
        TraceAttributes
            .Check(Of(key, AttributeValue.Text("value")), "emit")
            .Should().BeErr()
            .Which.Code.Should().Be(TraceErrorCode.InvalidInput);

    [Fact]
    public void Check_RejectsAKeyCarryingANul()
    {
        // The NUL is built at runtime on purpose: a literal control byte in source is a
        // corruption hazard, and the invariant is about the character, not its spelling.
        var key = "route" + (char)0 + "suffix";
        TraceAttributes
            .Check(Of(key, AttributeValue.Text("value")), "emit")
            .Should().BeErr()
            .Which.Message.Should().Contain("NUL-free");
    }

    [Fact]
    public void Check_AcceptsAKeyCarryingASpace() =>
        TraceAttributes.Check(Of("two words", AttributeValue.Text("value")), "emit").Should().BeOk();

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void Check_RejectsANonFiniteReal(double value) =>
        TraceAttributes
            .Check(Of("ratio", AttributeValue.Real(value)), "emit")
            .Should().BeErr()
            .Which.Message.Should().Contain("finite");

    [Fact]
    public void Check_AcceptsEveryOtherAttributeKind() =>
        TraceAttributes
            .Check(
                [
                    new("text", AttributeValue.Text("value")),
                    new("integer", AttributeValue.Integer(long.MaxValue)),
                    new("real", AttributeValue.Real(1.5)),
                    new("flag", AttributeValue.Flag(true)),
                    new("instant", AttributeValue.Instant(DateTimeOffset.UnixEpoch)),
                    new("duration", AttributeValue.Duration(TimeSpan.FromSeconds(90))),
                ],
                "emit")
            .Should().BeOk()
            .Which.Should().HaveCount(6);

    [Fact]
    public void Check_ReportsTheOperationItWasGiven() =>
        TraceAttributes
            .Check(Of(" ", AttributeValue.Text("x")), "flush")
            .Should().BeErr()
            .Which.Operation.Should().Be("flush");

    [Fact]
    public void Equal_ComparesByContentNotByOrderOrIdentity()
    {
        var left = TraceAttributes
            .Check([new("a", AttributeValue.Integer(1)), new("b", AttributeValue.Integer(2))], "emit")
            .Should().BeOk().Which;
        var right = TraceAttributes
            .Check([new("b", AttributeValue.Integer(2)), new("a", AttributeValue.Integer(1))], "emit")
            .Should().BeOk().Which;

        TraceAttributes.Equal(left, right).Should().BeTrue();
    }

    [Fact]
    public void Equal_IsFalseOnACountMismatch() =>
        TraceAttributes
            .Equal(Of("a", AttributeValue.Integer(1)), TraceAttributes.Empty)
            .Should().BeFalse();

    [Fact]
    public void Equal_IsFalseOnAMissingKey() =>
        TraceAttributes
            .Equal(Of("a", AttributeValue.Integer(1)), Of("b", AttributeValue.Integer(1)))
            .Should().BeFalse();

    [Fact]
    public void Equal_IsFalseOnADifferentValue() =>
        TraceAttributes
            .Equal(Of("a", AttributeValue.Integer(1)), Of("a", AttributeValue.Integer(2)))
            .Should().BeFalse();

    [Fact]
    public void Equal_RejectsNullMaps()
    {
        FluentActions.Invoking(() => TraceAttributes.Equal(null!, TraceAttributes.Empty))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => TraceAttributes.Equal(TraceAttributes.Empty, null!))
            .Should().Throw<ArgumentNullException>();
    }
}
