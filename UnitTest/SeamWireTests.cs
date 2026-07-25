namespace AtomiCloud.Diene.Interfaces.UnitTest;

public class SeamWireTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    [Fact]
    public void It_should_render_instants_as_rfc_3339_utc()
    {
        SeamWire.Instant(Anchor).Should().Be("2026-07-25T22:30:00.0000000Z");
    }

    [Fact]
    public void It_should_normalize_an_offset_instant_to_utc()
    {
        var offset = new DateTimeOffset(2026, 7, 26, 6, 30, 0, TimeSpan.FromHours(8));

        SeamWire.Instant(offset).Should().Be("2026-07-25T22:30:00.0000000Z");
    }

    [Fact]
    public void It_should_publish_the_instant_format()
    {
        SeamWire.InstantFormat.Should().Be("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'");
    }

    [Theory]
    [InlineData("2026-07-25T22:30:00.0000000Z")]
    [InlineData("2026-07-25T22:30:00Z")]
    [InlineData("2026-07-25T22:30:00.5Z")]
    [InlineData("2026-07-26T06:30:00+08:00")]
    public void It_should_parse_conformant_instants_into_utc(string wire)
    {
        SeamWire.ParseInstant(wire).Should().BeOk().Which.Offset.Should().Be(TimeSpan.Zero);
    }

    [Fact]
    public void It_should_round_trip_an_instant()
    {
        SeamWire.ParseInstant(SeamWire.Instant(Anchor)).Should().BeOk(Anchor);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("25/07/2026")]
    [InlineData("2026-07-25 22:30:00")]
    public void It_should_reject_a_non_conformant_instant(string wire)
    {
        SeamWire.ParseInstant(wire).Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Theory]
    [InlineData(90, "PT1M30S")]
    [InlineData(0, "PT0S")]
    [InlineData(3600, "PT1H")]
    public void It_should_render_durations_as_iso_8601(int seconds, string expected)
    {
        SeamWire.Duration(TimeSpan.FromSeconds(seconds)).Should().Be(expected);
    }

    [Fact]
    public void It_should_round_trip_a_duration()
    {
        SeamWire.ParseDuration("PT1M30S").Should().BeOk(TimeSpan.FromSeconds(90));
    }

    [Theory]
    [InlineData("")]
    [InlineData("  ")]
    [InlineData("90s")]
    [InlineData("PT99999999999999999999S")]
    [InlineData("P10675200D")]
    [InlineData("P99999999999999999999Y")]
    public void It_should_reject_a_non_conformant_duration(string wire)
    {
        SeamWire.ParseDuration(wire).Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_resolve_an_iana_timezone_id()
    {
        SeamWire.TimeZone(TimeZoneInfo.Utc.Id).Should().BeOk();
    }

    [Fact]
    public void It_should_reject_an_unknown_timezone_id()
    {
        SeamWire.TimeZone("Mars/Olympus").Should().BeSeamErr(SeamKind.Logging, "unknown_time_zone");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void It_should_reject_a_blank_timezone_id(string id)
    {
        SeamWire.TimeZone(id).Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Theory]
    [InlineData(SeamKind.System, "system")]
    [InlineData(SeamKind.Vfs, "vfs")]
    [InlineData(SeamKind.Terminal, "terminal")]
    [InlineData(SeamKind.Logging, "logging")]
    [InlineData(SeamKind.Metrics, "metrics")]
    public void It_should_name_and_parse_every_seam(SeamKind value, string wire)
    {
        SeamWire.Name(value).Should().Be(wire);
        SeamWire.ParseSeamKind(wire).Should().BeOk(value);
    }

    [Theory]
    [InlineData(LogLevel.Trace, "trace")]
    [InlineData(LogLevel.Debug, "debug")]
    [InlineData(LogLevel.Info, "info")]
    [InlineData(LogLevel.Warning, "warning")]
    [InlineData(LogLevel.Error, "error")]
    [InlineData(LogLevel.Fatal, "fatal")]
    public void It_should_name_and_parse_every_log_level(LogLevel value, string wire)
    {
        SeamWire.Name(value).Should().Be(wire);
        SeamWire.ParseLogLevel(wire).Should().BeOk(value);
    }

    [Theory]
    [InlineData(MetricKind.Counter, "counter")]
    [InlineData(MetricKind.Gauge, "gauge")]
    [InlineData(MetricKind.Histogram, "histogram")]
    public void It_should_name_and_parse_every_metric_kind(MetricKind value, string wire)
    {
        SeamWire.Name(value).Should().Be(wire);
        SeamWire.ParseMetricKind(wire).Should().BeOk(value);
    }

    [Theory]
    [InlineData(VfsEntryType.File, "file")]
    [InlineData(VfsEntryType.Directory, "directory")]
    [InlineData(VfsEntryType.Link, "link")]
    public void It_should_name_and_parse_every_entry_type(VfsEntryType value, string wire)
    {
        SeamWire.Name(value).Should().Be(wire);
        SeamWire.ParseVfsEntryType(wire).Should().BeOk(value);
    }

    [Theory]
    [InlineData(AttributeValueKind.Text, "text")]
    [InlineData(AttributeValueKind.Integer, "integer")]
    [InlineData(AttributeValueKind.Real, "real")]
    [InlineData(AttributeValueKind.Flag, "flag")]
    [InlineData(AttributeValueKind.Instant, "instant")]
    [InlineData(AttributeValueKind.Duration, "duration")]
    [InlineData(AttributeValueKind.TimeZone, "time_zone")]
    public void It_should_name_and_parse_every_attribute_kind(AttributeValueKind value, string wire)
    {
        SeamWire.Name(value).Should().Be(wire);
        SeamWire.ParseAttributeValueKind(wire).Should().BeOk(value);
    }

    [Fact]
    public void It_should_reject_unknown_wire_names()
    {
        SeamWire.ParseSeamKind("nope").Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
        SeamWire.ParseLogLevel("nope").Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
        SeamWire.ParseMetricKind("nope").Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
        SeamWire.ParseVfsEntryType("nope").Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
        SeamWire.ParseAttributeValueKind("nope").Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_refuse_to_name_a_value_outside_its_enumeration()
    {
        // Naming is a total function over DECLARED members; an undeclared value is a
        // caller contract violation, not a fallible seam operation, so it throws in
        // the same class as ArgumentNullException rather than returning a Result.
        var seam = () => SeamWire.Name((SeamKind)99);
        var level = () => SeamWire.Name((LogLevel)99);
        var metric = () => SeamWire.Name((MetricKind)99);
        var entry = () => SeamWire.Name((VfsEntryType)99);
        var attribute = () => SeamWire.Name((AttributeValueKind)99);

        seam.Should().Throw<ArgumentOutOfRangeException>();
        level.Should().Throw<ArgumentOutOfRangeException>();
        metric.Should().Throw<ArgumentOutOfRangeException>();
        entry.Should().Throw<ArgumentOutOfRangeException>();
        attribute.Should().Throw<ArgumentOutOfRangeException>();
    }
}
