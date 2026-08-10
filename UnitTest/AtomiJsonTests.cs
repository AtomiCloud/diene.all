using System.Text.Json;
using AtomiCloud.Diene.CoreUtils.Json;

namespace AtomiCloud.Diene.CoreUtils.UnitTest;

public class AtomiJsonTests
{
    private sealed record Payload
    {
        public DateOnly Date { get; init; }
        public TimeOnly Time { get; init; }
        public DateTimeOffset Instant { get; init; }
        public TimeSpan Duration { get; init; }
        public TimeZoneInfo Zone { get; init; } = TimeZoneInfo.Utc;
        public decimal Amount { get; init; }
        public long Identifier { get; init; }
    }

    private static Payload Sample() => new()
    {
        Date = new DateOnly(2026, 7, 25),
        Time = new TimeOnly(17, 30, 0),
        Instant = new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero),
        Duration = TimeSpan.FromMinutes(90),
        Zone = Wire.ParseTimeZone("Asia/Singapore").Get(),
        Amount = 1249.50m,
        Identifier = 9007199254740993L,
    };

    [Fact]
    public void It_should_write_every_wire_form_as_a_string()
    {
        var json = JsonSerializer.Serialize(Sample(), AtomiJson.DefaultOptions);

        json.Should().Be(
            """
            {"date":"2026-07-25","time":"17:30:00","instant":"2026-07-25T22:30:00Z","duration":"PT1H30M","zone":"Asia/Singapore","amount":"1249.50","identifier":"9007199254740993"}
            """);
    }

    [Fact]
    public void It_should_round_trip_a_payload_through_the_default_options()
    {
        var json = JsonSerializer.Serialize(Sample(), AtomiJson.DefaultOptions);

        JsonSerializer.Deserialize<Payload>(json, AtomiJson.DefaultOptions).Should().Be(Sample());
    }

    [Fact]
    public void It_should_apply_the_converters_to_options_a_caller_already_owns()
    {
        var options = new JsonSerializerOptions();
        AtomiJson.Apply(options);

        JsonSerializer.Serialize(new DateOnly(2026, 7, 25), options).Should().Be("\"2026-07-25\"");
    }

    [Fact]
    public void It_should_reject_null_options() =>
        FluentActions.Invoking(() => AtomiJson.Apply(null!)).Should().Throw<ArgumentNullException>();

    [Fact]
    public void It_should_refuse_a_caller_mutating_the_shared_options() =>
        FluentActions.Invoking(() => AtomiJson.DefaultOptions.Converters.Add(new WireDateConverter()))
            .Should().Throw<InvalidOperationException>();

    [Theory]
    [InlineData(typeof(DateOnly), "\"25-07-2026\"", "yyyy-MM-dd")]
    [InlineData(typeof(TimeOnly), "\"17:30\"", "HH:mm:ss")]
    [InlineData(typeof(DateTimeOffset), "\"2026-07-25 22:30:00Z\"", "RFC 3339 instant")]
    [InlineData(typeof(TimeSpan), "\"P1Y\"", "ISO 8601 duration")]
    [InlineData(typeof(TimeZoneInfo), "\"Middle/Earth\"", "IANA timezone id")]
    [InlineData(typeof(decimal), "\"1,249.50\"", "decimal string")]
    [InlineData(typeof(long), "\"1.5\"", "int64 string")]
    public void It_should_surface_a_rejected_payload_as_a_json_exception(Type type, string json, string expected) =>
        FluentActions.Invoking(() => JsonSerializer.Deserialize(json, type, AtomiJson.DefaultOptions))
            .Should().Throw<JsonException>().WithMessage($"expected {expected}*");

    [Theory]
    [InlineData(typeof(DateOnly), "DateOnly")]
    [InlineData(typeof(TimeOnly), "TimeOnly")]
    [InlineData(typeof(DateTimeOffset), "DateTimeOffset")]
    [InlineData(typeof(TimeSpan), "TimeSpan")]
    [InlineData(typeof(TimeZoneInfo), "TimeZoneInfo")]
    public void It_should_refuse_a_wire_value_that_is_not_a_json_string(Type type, string name) =>
        FluentActions.Invoking(() => JsonSerializer.Deserialize("42", type, AtomiJson.DefaultOptions))
            .Should().Throw<JsonException>().WithMessage($"{name} must arrive as a JSON string*");

    [Theory]
    [InlineData(typeof(decimal), "decimal")]
    [InlineData(typeof(long), "int64")]
    public void It_should_refuse_a_number_wire_value_that_is_neither_string_nor_number(Type type, string name) =>
        FluentActions.Invoking(() => JsonSerializer.Deserialize("true", type, AtomiJson.DefaultOptions))
            .Should().Throw<JsonException>().WithMessage($"{name} must arrive as a JSON string*");

    [Fact]
    public void It_should_still_read_a_number_from_a_peer_that_has_not_adopted_the_contract()
    {
        JsonSerializer.Deserialize<decimal>("1249.50", AtomiJson.DefaultOptions).Should().Be(1249.50m);
        JsonSerializer.Deserialize<long>("42", AtomiJson.DefaultOptions).Should().Be(42L);
    }
}
