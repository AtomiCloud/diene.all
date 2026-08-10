using System.Text.Json;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.UnitTest;

/// <summary>
/// Pins the canonical block against a checked-in fixture. .NET is the reference
/// binding for the <c>otel:</c> block, so a rename here is a cross-language contract
/// change and has to fail loudly rather than drift.
/// </summary>
public class C0OtelBlockFixtureTests
{
    private static JsonElement Fixture { get; } = JsonDocument
        .Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "otel-block-v1.json")))
        .RootElement;

    private static IReadOnlyDictionary<string, string> Entries(string property) =>
        Fixture.GetProperty(property).EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetString()!);

    [Fact]
    public void Section_MatchesTheOptionKey() =>
        Fixture.GetProperty("section").GetString().Should().Be(OtelOption.Key);

    [Fact]
    public void EveryPinnedPathBindsToTheOptionsGraph()
    {
        var paths = Entries("paths");
        var values = paths.Values.ToDictionary(
            path => path,
            path => path.EndsWith("Ratio", StringComparison.Ordinal) ? "0.5"
                : path.EndsWith("Interval", StringComparison.Ordinal) ? "PT30S"
                : path.EndsWith("Timeout", StringComparison.Ordinal) ? "PT5S"
                : path.EndsWith("Endpoint", StringComparison.Ordinal) ? "http://collector:4318"
                : path.EndsWith("Protocol", StringComparison.Ordinal) ? "http/protobuf"
                : path.EndsWith("Type", StringComparison.Ordinal) ? "always_on"
                : "true",
            StringComparer.Ordinal);

        var option = new ConfigurationBuilder()
            .AddInMemoryCollection(values.Select(entry => new KeyValuePair<string, string?>(entry.Key, entry.Value)))
            .Build()
            .GetSection(OtelOption.Key)
            .Get<OtelOption>();

        option.Should().NotBeNull();
        option!.Logs.Exporter.Otlp.Endpoint.Should().Be("http://collector:4318");
        option.Logs.Exporter.Otlp.Timeout.Should().Be("PT5S");
        option.Metrics.Interval.Should().Be("PT30S");
        option.Traces.Sampler.Type.Should().Be("always_on");
        option.Traces.Sampler.Ratio.Should().Be(0.5);
        option.Traces.Exporter.Otlp.Enabled.Should().BeTrue();
    }

    [Fact]
    public void EveryPinnedEnvNameIsThePrefixedDoubleUnderscoreSpellingOfItsPath()
    {
        var prefix = Fixture.GetProperty("envPrefix").GetString()!;
        var paths = Entries("paths");

        foreach (var (key, variable) in Entries("envNames"))
        {
            paths.Should().ContainKey(key);
            variable.Should().Be(prefix + paths[key].Replace(':', '_').Replace("_", "__", StringComparison.Ordinal)
                .ToUpperInvariant());
        }
    }

    [Fact]
    public void PinnedDefaultsMatchTheShippedOptionDefaults()
    {
        var defaults = Fixture.GetProperty("defaults");
        var option = new OtelOption();

        option.Logs.Enabled.Should().Be(defaults.GetProperty("signalEnabled").GetBoolean());
        option.Logs.Exporter.Console.Enabled.Should().Be(defaults.GetProperty("consoleEnabled").GetBoolean());
        option.Logs.Exporter.Otlp.Enabled.Should().Be(defaults.GetProperty("otlpEnabled").GetBoolean());
        option.Logs.Exporter.Otlp.Endpoint.Should().Be(defaults.GetProperty("otlpEndpoint").GetString());
        option.Logs.Exporter.Otlp.Protocol.Should().Be(defaults.GetProperty("otlpProtocol").GetString());
        option.Logs.Exporter.Otlp.Timeout.Should().Be(defaults.GetProperty("otlpTimeout").GetString());
        option.Metrics.Interval.Should().Be(defaults.GetProperty("metricsInterval").GetString());
        option.Traces.Sampler.Type.Should().Be(defaults.GetProperty("samplerType").GetString());
        option.Traces.Sampler.Ratio.Should().Be(defaults.GetProperty("samplerRatio").GetDouble());
    }

    [Fact]
    public void PinnedSamplerTypesAreExactlyTheOnesTheEngineMaps()
    {
        var types = Fixture.GetProperty("samplerTypes").EnumerateArray().Select(t => t.GetString()).ToArray();
        types.Should().BeEquivalentTo([
            OtelSampler.ParentBasedTraceIdRatio,
            OtelSampler.AlwaysOn,
            OtelSampler.AlwaysOff,
        ]);

        foreach (var type in types)
        {
            OtelSampler.Create(new SamplerOption { Type = type! }, Env.None).Should().BeOk();
        }
    }

    [Fact]
    public void PinnedResourceKeysAreExactlyTheMappedKeys() =>
        Fixture
            .GetProperty("resourceKeys")
            .EnumerateArray()
            .Select(key => key.GetString())
            .Should().BeEquivalentTo(AtomiResource.Map(new AppIdentity("l", "p", "s", "m", "v")).Keys);

    [Fact]
    public void PinnedProtocolMatchesTheHostExtensionConstant() =>
        Fixture
            .GetProperty("defaults")
            .GetProperty("otlpProtocol")
            .GetString()
            .Should().Be(OtelHostExtensions.OtlpProtocol);
}
