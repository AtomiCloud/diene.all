using System.Text.Json;

namespace AtomiCloud.Diene.Interfaces.UnitTest;

/// <summary>
/// Pins the C0 wire contract (R14) to a versioned, source-owned fixture:
/// RFC 3339 UTC instants, ISO 8601 durations, IANA timezone ids, and one stable
/// lowercase name per enumeration. The fixture is explicitly
/// <c>local-regression-only</c> — it does not claim a shared cross-language
/// fixture or an external C0 proof.
/// </summary>
public class C0SeamWireFixtureTests
{
    private static readonly JsonElement Fixture = Load();

    private static JsonElement Load()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(
            Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "seam-wire-v1.json")));
        return document.RootElement.Clone();
    }

    private static string[] Names(string property) =>
        [.. Fixture.GetProperty(property).EnumerateArray().Select(element => element.GetString()!)];

    [Fact]
    public void It_should_declare_its_version_and_status()
    {
        Fixture.GetProperty("version").GetInt32().Should().Be(1);
        Fixture.GetProperty("status").GetString().Should().Be("local-regression-only");
    }

    [Fact]
    public void It_should_pin_the_seam_wire_names()
    {
        Names("seams").Select(name => SeamWire.ParseSeamKind(name).Should().BeOk().Which)
            .Should().Equal(Enum.GetValues<SeamKind>());
    }

    [Fact]
    public void It_should_pin_the_log_level_wire_names()
    {
        Names("logLevels").Select(name => SeamWire.ParseLogLevel(name).Should().BeOk().Which)
            .Should().Equal(Enum.GetValues<LogLevel>());
    }

    [Fact]
    public void It_should_pin_the_metric_kind_wire_names()
    {
        Names("metricKinds").Select(name => SeamWire.ParseMetricKind(name).Should().BeOk().Which)
            .Should().Equal(Enum.GetValues<MetricKind>());
    }

    [Fact]
    public void It_should_pin_the_entry_type_wire_names()
    {
        Names("vfsEntryTypes").Select(name => SeamWire.ParseVfsEntryType(name).Should().BeOk().Which)
            .Should().Equal(Enum.GetValues<VfsEntryType>());
    }

    [Fact]
    public void It_should_pin_the_attribute_kind_wire_names()
    {
        Names("attributeKinds").Select(name => SeamWire.ParseAttributeValueKind(name).Should().BeOk().Which)
            .Should().Equal(Enum.GetValues<AttributeValueKind>());
    }

    [Fact]
    public void It_should_round_trip_the_pinned_instant()
    {
        var wire = Fixture.GetProperty("instant").GetString()!;

        var parsed = SeamWire.ParseInstant(wire).Should().BeOk().Which;

        parsed.Offset.Should().Be(TimeSpan.Zero);
        SeamWire.Instant(parsed).Should().Be(wire);
    }

    [Fact]
    public void It_should_round_trip_the_pinned_duration()
    {
        var wire = Fixture.GetProperty("duration").GetString()!;

        SeamWire.Duration(SeamWire.ParseDuration(wire).Should().BeOk().Which).Should().Be(wire);
    }

    [Fact]
    public void It_should_resolve_the_pinned_iana_timezone()
    {
        SeamWire.TimeZone(Fixture.GetProperty("timeZone").GetString()!).Should().BeOk();
    }

    [Fact]
    public void It_should_round_trip_every_pinned_attribute_payload()
    {
        foreach (var entry in Fixture.GetProperty("attributes").EnumerateObject())
        {
            var kind = SeamWire.ParseAttributeValueKind(entry.Name).Should().BeOk().Which;
            var wire = entry.Value.GetString()!;

            var value = AttributeValue.FromWire(kind, wire).Should().BeOk().Which;

            value.Kind.Should().Be(kind);
            value.Wire.Should().Be(wire);
        }
    }

    [Fact]
    public void It_should_cover_every_attribute_kind_with_a_pinned_payload()
    {
        Fixture.GetProperty("attributes").EnumerateObject().Select(entry => entry.Name)
            .Should().BeEquivalentTo(Enum.GetValues<AttributeValueKind>().Select(SeamWire.Name));
    }
}
