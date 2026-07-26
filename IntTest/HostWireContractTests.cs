using System.Text.Json;
using AtomiCloud.Diene.Interfaces;
using AtomiCloud.Diene.Interfaces.TestHelper;

namespace AtomiCloud.Diene.CoreUtils.IntTest;

/// <summary>
/// INT tier — the parts of the contract that are only real against the host.
/// Timezone resolution reads the machine's IANA database rather than a table this
/// repository controls, and the pinned fixture is loaded off a real filesystem,
/// so a host without tzdata or a fixture that drifts turns this tier red while
/// the pure unit tier stays green.
/// </summary>
public class HostWireContractTests
{
    private static JsonElement Fixture { get; } = JsonDocument
        .Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "wire-v1.json")))
        .RootElement;

    [Fact]
    public void It_should_resolve_the_pinned_zone_against_the_host_iana_database()
    {
        var id = Fixture.GetProperty("timeZone").GetString()!;

        var zone = Wire.ParseTimeZone(id).Should().BeOk().Which;

        zone.HasIanaId.Should().BeTrue();
        zone.GetUtcOffset(new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero)).Should().Be(TimeSpan.FromHours(8));
    }

    [Fact]
    public void It_should_refuse_a_windows_zone_id_even_where_the_host_can_map_it() =>
        Wire.ParseTimeZone("Singapore Standard Time").Should()
            .BeErr(new WireFormatError("IANA timezone id", "Singapore Standard Time"));

    [Fact]
    public void It_should_round_trip_the_demo_receipt_through_the_fixture_pinned_forms()
    {
        var receipt = Samples.Sample().Should().BeOk().Which;

        var json = JsonDocument.Parse(Samples.ToWire(receipt)).RootElement;

        json.GetProperty("shippedOn").GetString().Should().Be(Fixture.GetProperty("date").GetString());
        json.GetProperty("cutoff").GetString().Should().Be(Fixture.GetProperty("time").GetString());
        json.GetProperty("confirmedAt").GetString().Should().Be(Fixture.GetProperty("instant").GetString());
        json.GetProperty("originZone").GetString().Should().Be(Fixture.GetProperty("timeZone").GetString());
        json.GetProperty("declaredValue").GetString().Should().Be(Fixture.GetProperty("decimal").GetString());
        json.GetProperty("trackingNumber").GetString().Should().Be(Fixture.GetProperty("int64").GetString());
        json.GetProperty("transitTime").GetString().Should().Be("PT1H30M");

        Samples.FromWire(Samples.ToWire(receipt)).Should().BeOk(receipt);
    }

    [Fact]
    public void It_should_report_a_malformed_payload_instead_of_throwing() =>
        Samples.FromWire("""{"shippedOn":"25-07-2026"}""").Should().BeErr()
            .Which.Expected.Should().Be("shipment receipt");

    [Fact]
    public void It_should_report_a_null_payload_as_a_rejected_receipt() =>
        Samples.FromWire("null").Should().BeErr(new WireFormatError("shipment receipt", "null"));

    [Fact]
    public void It_should_compose_a_catalog_key_from_untrusted_text()
    {
        Samples.CatalogKey("AtomiCloud", "Express Parcel").Should().BeOk("atomicloud:express-parcel");
        Samples.CatalogKey("!!!", "Express Parcel").Should().BeErr(new KeyError("namespace must not be empty", "!!!"));
    }

    [Fact]
    public void It_should_deliver_normalized_wire_attributes_to_a_seam()
    {
        var receipt = Samples.Sample().Should().BeOk().Which;
        var sink = new InMemoryLoggerSink();

        var attributes = Samples.Telemetry(receipt).Should().BeOk().Which;
        sink.Emit(new LogRecord(receipt.ConfirmedAt, LogLevel.Info, "shipment confirmed", attributes)).Should().BeOk();

        var recorded = sink.Records.Should().ContainSingle().Which.Attributes;
        recorded.Keys.Should().BeEquivalentTo(
            "shipmentreference", "shippedon", "dailycutoff", "declaredvalue",
            "confirmedat", "transittime", "trackingnumber");
        recorded["declaredvalue"].Wire.Should().Be(Fixture.GetProperty("decimal").GetString());
        recorded["confirmedat"].Kind.Should().Be(AttributeValueKind.Instant);
    }

    [Fact]
    public void It_should_reject_a_null_receipt_in_telemetry() =>
        FluentActions.Invoking(() => Samples.Telemetry(null!)).Should().Throw<ArgumentNullException>();

    [Fact]
    public void It_should_read_an_attribute_back_under_a_different_key_spelling()
    {
        var receipt = Samples.Sample().Should().BeOk().Which;
        var attributes = Samples.Telemetry(receipt).Should().BeOk().Which;

        Samples.Lookup(attributes, "TrackingNumber").Should().BeOk()
            .Which.Wire.Should().Be(Fixture.GetProperty("int64").GetString());
        Samples.Lookup(attributes, "shipped-on").Should().BeOk()
            .Which.Wire.Should().Be(Fixture.GetProperty("date").GetString());
    }

    [Fact]
    public void It_should_report_an_attribute_key_that_matches_nothing()
    {
        var receipt = Samples.Sample().Should().BeOk().Which;
        var attributes = Samples.Telemetry(receipt).Should().BeOk().Which;

        var missing = Samples.Lookup(attributes, "carrier").Should().BeErr().Which;

        missing.Reason.Should().Be("no attribute matches the key");
        missing.Offending.Should().Be("carrier");
    }

    [Fact]
    public void It_should_reject_a_null_attribute_map_in_lookup() =>
        FluentActions.Invoking(() => Samples.Lookup(null!, "key")).Should().Throw<ArgumentNullException>();
}
