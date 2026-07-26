using System.Text.Json;
using System.Text.Json.Nodes;
using Json.Schema;

namespace AtomiCloud.DotnetBase.UnitTest;

/// <summary>
/// Validates real documents against the SHIPPED JSON Schema with a standards
/// compliant Draft 2020-12 validator, rather than against the Options binding.
/// The distinction is what let a defect through: the binder ignores keys a schema
/// rejects, so every binding test stayed green while the schema itself refused
/// <c>metrics.interval</c> and <c>traces.sampler</c>. The cause was composing each
/// signal with <c>allOf</c> onto a base carrying <c>additionalProperties:false</c>
/// — <c>allOf</c> does not merge property sets, so the base saw those keys as
/// unknown. Only a real validator proves that semantics; a hand-rolled subset
/// would have agreed with the mistake.
/// </summary>
public class OtelBlockSchemaValidationTests
{
    private static JsonSchema Schema { get; } = JsonSchema.FromText(OtelBlockSchema.Json);

    private static EvaluationOptions Options { get; } = new() { OutputFormat = OutputFormat.Hierarchical };

    /// <summary>The full canonical block: every signal populated, every C0 default present.</summary>
    public static JsonObject Canonical() => new()
    {
        ["logs"] = new JsonObject
        {
            ["enabled"] = true,
            ["exporter"] = Exporter(),
        },
        ["metrics"] = new JsonObject
        {
            ["enabled"] = true,
            ["interval"] = "PT60S",
            ["exporter"] = Exporter(),
        },
        ["traces"] = new JsonObject
        {
            ["enabled"] = true,
            ["sampler"] = new JsonObject
            {
                ["type"] = "parentbased_traceidratio",
                ["ratio"] = 1.0,
            },
            ["exporter"] = Exporter(),
        },
    };

    private static JsonObject Exporter() => new()
    {
        ["console"] = new JsonObject { ["enabled"] = false },
        ["otlp"] = new JsonObject
        {
            ["enabled"] = false,
            ["endpoint"] = "",
            ["protocol"] = "http/protobuf",
            ["headers"] = new JsonObject(),
            ["timeout"] = "PT10S",
        },
    };

    private static bool Valid(JsonNode document) =>
        Schema.Evaluate(JsonSerializer.Deserialize<JsonElement>(document), Options).IsValid;

    [Fact]
    public void Schema_AcceptsTheFullCanonicalBlock() => Valid(Canonical()).Should().BeTrue();

    [Fact]
    public void Schema_AcceptsTheTwoSignalSpecificKeysThatCompositionRejected()
    {
        // The exact regression: with allOf these two were "additional properties".
        Valid(new JsonObject { ["metrics"] = new JsonObject { ["interval"] = "PT30S" } }).Should().BeTrue();
        Valid(new JsonObject
        {
            ["traces"] = new JsonObject { ["sampler"] = new JsonObject { ["type"] = "always_on" } },
        }).Should().BeTrue();
    }

    [Fact]
    public void Schema_AcceptsAnEmptyBlockBecauseEveryKeyHasADefault() =>
        Valid(new JsonObject()).Should().BeTrue();

    [Fact]
    public void Schema_StillRejectsAnUnknownKey()
    {
        // Assert-the-asserter: if the fix had simply dropped additionalProperties:false,
        // every acceptance case above would pass vacuously.
        Valid(new JsonObject { ["logs"] = new JsonObject { ["bogus"] = true } }).Should().BeFalse();
        Valid(new JsonObject { ["profiling"] = true }).Should().BeFalse();
    }

    [Fact]
    public void Schema_RejectsASignalSpecificKeyOnTheWrongSignal()
    {
        Valid(new JsonObject { ["logs"] = new JsonObject { ["interval"] = "PT60S" } }).Should().BeFalse();
        Valid(new JsonObject
        {
            ["metrics"] = new JsonObject { ["sampler"] = new JsonObject { ["type"] = "always_on" } },
        }).Should().BeFalse();
    }

    [Theory]
    [InlineData("60s")]
    [InlineData("P1M")]
    public void Schema_RejectsANonIso8601Interval(string interval) =>
        Valid(new JsonObject { ["metrics"] = new JsonObject { ["interval"] = interval } }).Should().BeFalse();

    [Fact]
    public void Schema_RejectsANonFleetProtocol() =>
        Valid(new JsonObject
        {
            ["logs"] = new JsonObject
            {
                ["exporter"] = new JsonObject { ["otlp"] = new JsonObject { ["protocol"] = "grpc" } },
            },
        }).Should().BeFalse();

    [Theory]
    [InlineData("coin_flip")]
    [InlineData("traceidratio")]
    public void Schema_RejectsAnUnsupportedSamplerType(string type) =>
        Valid(new JsonObject
        {
            ["traces"] = new JsonObject { ["sampler"] = new JsonObject { ["type"] = type } },
        }).Should().BeFalse();

    [Theory]
    [InlineData(-0.1)]
    [InlineData(1.1)]
    public void Schema_RejectsARatioOutsideTheUnitInterval(double ratio) =>
        Valid(new JsonObject
        {
            ["traces"] = new JsonObject { ["sampler"] = new JsonObject { ["ratio"] = ratio } },
        }).Should().BeFalse();

    [Fact]
    public void Schema_RejectsAWrongTypedValue() =>
        Valid(new JsonObject { ["logs"] = new JsonObject { ["enabled"] = "yes" } }).Should().BeFalse();

    [Fact]
    public void Schema_DeclaresEverySignalStandaloneRatherThanComposed()
    {
        // Pins the shape as well as the behaviour: an editor reaching for allOf again
        // reintroduces the defect, and this fails before it reaches a consumer.
        var document = JsonNode.Parse(OtelBlockSchema.Json)!.AsObject();
        var properties = document["properties"]!.AsObject();

        foreach (var signal in new[] { "logs", "metrics", "traces" })
        {
            var declared = properties[signal]!.AsObject();
            declared.Should().NotContainKey("allOf", $"'{signal}' must not compose a base schema");
            declared["additionalProperties"]!.GetValue<bool>().Should().BeFalse();
            declared["properties"]!.AsObject().Should().ContainKeys("enabled", "exporter");
        }

        properties["metrics"]!["properties"]!.AsObject().Should().ContainKey("interval");
        properties["traces"]!["properties"]!.AsObject().Should().ContainKey("sampler");
        document["$defs"]!.AsObject().Should().NotContainKey("signal");
    }

    [Fact]
    public void SchemaDefaults_MatchTheShippedOptionDefaults()
    {
        var document = JsonNode.Parse(OtelBlockSchema.Json)!.AsObject();
        var option = new OtelOption();

        document["properties"]!["metrics"]!["properties"]!["interval"]!["default"]!.GetValue<string>()
            .Should().Be(option.Metrics.Interval);

        var sampler = document["$defs"]!["sampler"]!["properties"]!;
        sampler["type"]!["default"]!.GetValue<string>().Should().Be(option.Traces.Sampler.Type);
        sampler["ratio"]!["default"]!.GetValue<double>().Should().Be(option.Traces.Sampler.Ratio);

        var otlp = document["$defs"]!["exporter"]!["properties"]!["otlp"]!["properties"]!;
        otlp["protocol"]!["default"]!.GetValue<string>().Should().Be(option.Logs.Exporter.Otlp.Protocol);
        otlp["timeout"]!["default"]!.GetValue<string>().Should().Be(option.Logs.Exporter.Otlp.Timeout);
        otlp["enabled"]!["default"]!.GetValue<bool>().Should().Be(option.Logs.Exporter.Otlp.Enabled);
    }
}
