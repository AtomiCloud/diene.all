using System.Text.Json;

namespace AtomiCloud.Diene.Interfaces.IntTest;

/// <summary>
/// INT tier — the source-owned C0 wire fixture is round-tripped through a REAL
/// filesystem seam, so the R14 contract is proven across the host boundary and not
/// only in memory. The fixture is explicitly <c>local-regression-only</c>.
/// </summary>
public class C0WireFixtureRoundTrip
{
    [Fact]
    public async Task It_should_round_trip_every_pinned_wire_value_through_the_host_filesystem()
    {
        var token = TestContext.Current.CancellationToken;
        var vfs = new App.Adapters.HostVfs();
        var source = Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "seam-wire-v1.json");
        var scratch = Path.Combine(Path.GetTempPath(), $"diene-interfaces-c0-{Guid.NewGuid():N}");
        var copy = Path.Combine(scratch, "seam-wire-v1.json");

        try
        {
            var read = await vfs.ReadText(source, token);
            read.Should().BeOk();
            (await vfs.WriteText(copy, read.Get(), new VfsWriteOptions(true), token)).Should().BeOk();

            var reread = await vfs.ReadText(copy, token);
            reread.Should().BeOk(read.Get());

            using var document = JsonDocument.Parse(reread.Get());
            var fixture = document.RootElement;

            fixture.GetProperty("version").GetInt32().Should().Be(1);
            fixture.GetProperty("status").GetString().Should().Be("local-regression-only");

            var instant = fixture.GetProperty("instant").GetString()!;
            SeamWire.Instant(SeamWire.ParseInstant(instant).Should().BeOk().Which).Should().Be(instant);

            var duration = fixture.GetProperty("duration").GetString()!;
            SeamWire.Duration(SeamWire.ParseDuration(duration).Should().BeOk().Which).Should().Be(duration);

            SeamWire.TimeZone(fixture.GetProperty("timeZone").GetString()!).Should().BeOk();

            foreach (var entry in fixture.GetProperty("attributes").EnumerateObject())
            {
                var kind = SeamWire.ParseAttributeValueKind(entry.Name).Should().BeOk().Which;
                var value = AttributeValue.FromWire(kind, entry.Value.GetString()!).Should().BeOk().Which;
                value.Wire.Should().Be(entry.Value.GetString());
            }
        }
        finally
        {
            if (Directory.Exists(scratch)) Directory.Delete(scratch, true);
        }
    }

    [Fact]
    public async Task It_should_carry_a_full_attribute_set_through_a_host_backed_sink()
    {
        await using var writer = new StringWriter();
        var sink = new App.Adapters.TextWriterLoggerSink(writer);
        var instant = new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

        sink.Emit(new LogRecord(
            instant,
            LogLevel.Warning,
            "wire",
            SeamContracts.SampleAttributes(instant),
            "boom",
            "at wire")).Should().BeOk();

        var rendered = writer.ToString();
        rendered.Should().Contain("2026-07-25T22:30:00.0000000Z warning wire");
        rendered.Should().Contain("duration=duration:PT1M30S");
        rendered.Should().Contain("error=boom");
        rendered.Should().Contain("stack=at wire");
    }
}
