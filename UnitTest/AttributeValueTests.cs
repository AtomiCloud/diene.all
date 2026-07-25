namespace AtomiCloud.Diene.Interfaces.UnitTest;

public class AttributeValueTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    [Fact]
    public void It_should_store_text_verbatim()
    {
        var value = AttributeValue.Text("value");

        value.Kind.Should().Be(AttributeValueKind.Text);
        value.Wire.Should().Be("value");
        value.AsText().Should().Be("value");
    }

    [Fact]
    public void It_should_reject_null_text()
    {
        var act = () => AttributeValue.Text(null!);

        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_render_an_uninitialized_value_as_empty_text()
    {
        default(AttributeValue).Wire.Should().BeEmpty();
    }

    [Fact]
    public void It_should_round_trip_every_kind()
    {
        AttributeValue.Integer(42).AsInteger().Should().BeOk(42L);
        AttributeValue.Real(1.5).AsReal().Should().BeOk(1.5);
        AttributeValue.Flag(true).AsFlag().Should().BeOk(true);
        AttributeValue.Flag(false).AsFlag().Should().BeOk(false);
        AttributeValue.Instant(Anchor).AsInstant().Should().BeOk(Anchor);
        AttributeValue.Duration(TimeSpan.FromSeconds(90)).AsDuration().Should().BeOk(TimeSpan.FromSeconds(90));
        AttributeValue.TimeZone(TimeZoneInfo.Utc.Id).Should().BeOk().Which.AsTimeZone().Should().BeOk();
    }

    [Fact]
    public void It_should_use_c0_wire_forms()
    {
        AttributeValue.Integer(42).Wire.Should().Be("42");
        AttributeValue.Real(1.5).Wire.Should().Be("1.5");
        AttributeValue.Flag(true).Wire.Should().Be("true");
        AttributeValue.Flag(false).Wire.Should().Be("false");
        AttributeValue.Instant(Anchor).Wire.Should().Be("2026-07-25T22:30:00.0000000Z");
        AttributeValue.Duration(TimeSpan.FromSeconds(90)).Wire.Should().Be("PT1M30S");
    }

    [Fact]
    public void It_should_reject_an_unresolvable_timezone()
    {
        AttributeValue.TimeZone("Mars/Olympus").Should().BeSeamErr(SeamKind.Logging, "unknown_time_zone");
    }

    [Fact]
    public void It_should_refuse_to_read_a_value_as_the_wrong_kind()
    {
        var text = AttributeValue.Text("value");

        text.AsInteger().Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
        text.AsReal().Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
        text.AsFlag().Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
        text.AsInstant().Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
        text.AsDuration().Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
        text.AsTimeZone().Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_rebuild_every_kind_from_the_wire()
    {
        AttributeValue.FromWire(AttributeValueKind.Text, "value").Should().BeOk(AttributeValue.Text("value"));
        AttributeValue.FromWire(AttributeValueKind.Integer, "42").Should().BeOk(AttributeValue.Integer(42));
        AttributeValue.FromWire(AttributeValueKind.Real, "1.5").Should().BeOk(AttributeValue.Real(1.5));
        AttributeValue.FromWire(AttributeValueKind.Flag, "true").Should().BeOk(AttributeValue.Flag(true));
        AttributeValue.FromWire(AttributeValueKind.Flag, "false").Should().BeOk(AttributeValue.Flag(false));
        AttributeValue.FromWire(AttributeValueKind.Instant, SeamWire.Instant(Anchor))
            .Should().BeOk(AttributeValue.Instant(Anchor));
        AttributeValue.FromWire(AttributeValueKind.Duration, "PT1M30S")
            .Should().BeOk(AttributeValue.Duration(TimeSpan.FromSeconds(90)));
        AttributeValue.FromWire(AttributeValueKind.TimeZone, TimeZoneInfo.Utc.Id).Should().BeOk();
    }

    [Theory]
    [InlineData(AttributeValueKind.Integer, "twelve")]
    [InlineData(AttributeValueKind.Real, "one point five")]
    [InlineData(AttributeValueKind.Flag, "yes")]
    [InlineData(AttributeValueKind.Instant, "yesterday")]
    [InlineData(AttributeValueKind.Duration, "90s")]
    public void It_should_reject_a_malformed_wire_payload(AttributeValueKind kind, string wire)
    {
        AttributeValue.FromWire(kind, wire).Should().BeErr();
    }

    [Fact]
    public void It_should_reject_an_undeclared_wire_kind()
    {
        AttributeValue.FromWire((AttributeValueKind)99, "value")
            .Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_reject_an_unresolvable_timezone_from_the_wire()
    {
        AttributeValue.FromWire(AttributeValueKind.TimeZone, "Mars/Olympus")
            .Should().BeSeamErr(SeamKind.Logging, "unknown_time_zone");
    }

    [Fact]
    public void It_should_be_equal_by_kind_and_wire()
    {
        var left = AttributeValue.Integer(42);
        var right = AttributeValue.Integer(42);
        var other = AttributeValue.Text("42");

        left.Equals(right).Should().BeTrue();
        left.Equals((object)right).Should().BeTrue();
        left.Equals("42").Should().BeFalse();
        (left == right).Should().BeTrue();
        (left != other).Should().BeTrue();
        left.GetHashCode().Should().Be(right.GetHashCode());
        left.Equals(other).Should().BeFalse();
    }

    [Fact]
    public void It_should_render_kind_and_wire()
    {
        AttributeValue.Duration(TimeSpan.FromSeconds(90)).ToString().Should().Be("duration:PT1M30S");
    }

    [Fact]
    public void It_should_copy_attribute_maps_in_key_order()
    {
        var attributes = SeamAttributes.Copy(
        [
            new("beta", AttributeValue.Integer(2)),
            new("alpha", AttributeValue.Integer(1)),
        ]);

        attributes.Keys.Should().ContainInOrder("alpha", "beta");
        SeamAttributes.Copy(null).Should().BeSameAs(SeamAttributes.Empty);
        SeamAttributes.Empty.Should().BeEmpty();
    }
}
