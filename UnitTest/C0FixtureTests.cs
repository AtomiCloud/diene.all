using System.Text.Json;

namespace AtomiCloud.Diene.CoreUtils.UnitTest;

/// <summary>
/// The pinned C0 §1 payloads. A change to a canonical spelling has to change this
/// fixture too, so drift is a visible edit rather than a silent behavior change.
/// </summary>
public class C0FixtureTests
{
    private static JsonElement Fixture { get; } = JsonDocument
        .Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "wire-v1.json")))
        .RootElement;

    private static string Value(string name) => Fixture.GetProperty(name).GetString()!;

    [Fact]
    public void It_should_pin_the_fixture_contract_version()
    {
        Fixture.GetProperty("version").GetInt32().Should().Be(1);
        Fixture.GetProperty("status").GetString().Should().Be("local-regression-only");
    }

    [Theory]
    [InlineData("date")]
    [InlineData("time")]
    [InlineData("instant")]
    [InlineData("instantWithFraction")]
    [InlineData("duration")]
    [InlineData("durationWithDays")]
    [InlineData("timeZone")]
    [InlineData("decimal")]
    [InlineData("int64")]
    public void It_should_round_trip_every_pinned_wire_value(string name)
    {
        var wire = Value(name);

        var rendered = name switch
        {
            "date" => Wire.Format(Wire.ParseDate(wire).Should().BeOk().Which),
            "time" => Wire.Format(Wire.ParseTime(wire).Should().BeOk().Which),
            "instant" or "instantWithFraction" => Wire.Format(Wire.ParseInstant(wire).Should().BeOk().Which),
            "duration" or "durationWithDays" => Wire.Format(Wire.ParseDuration(wire).Should().BeOk().Which),
            "timeZone" => Wire.Format(Wire.ParseTimeZone(wire).Should().BeOk().Which),
            "decimal" => Wire.Format(Wire.ParseDecimal(wire).Should().BeOk().Which),
            _ => Wire.Format(Wire.ParseInt64(wire).Should().BeOk().Which),
        };

        rendered.Should().Be(wire);
    }

    [Fact]
    public void It_should_normalize_the_pinned_offset_instant_onto_the_pinned_utc_instant() =>
        Wire.Format(Wire.ParseInstant(Value("instantWithOffset")).Should().BeOk().Which)
            .Should().Be(Value("instant"));

    [Fact]
    public void It_should_reproduce_the_pinned_cross_language_slugs()
    {
        foreach (var entry in Fixture.GetProperty("slugs").EnumerateObject())
            Slug.Slugify(entry.Name).Should().Be(entry.Value.GetString());
    }

    [Fact]
    public void It_should_reproduce_the_pinned_canonical_keys()
    {
        foreach (var entry in Fixture.GetProperty("keys").EnumerateObject())
            KeyNormalizer.Canonical(entry.Name).Should().Be(entry.Value.GetString());
    }
}
