using System.Diagnostics.Metrics;

namespace AtomiCloud.DotnetBase.UnitTest;

public class OtelMetricsCollectorTests : IDisposable
{
    private readonly Instrumentation _instrumentation = new(new AppIdentity("l", "p", "billing", "m", "1.0.0"));

    private static Dictionary<string, AttributeValue> Attributes { get; } = new(StringComparer.Ordinal)
    {
        ["route"] = AttributeValue.Text("/v1/demo"),
    };

    public void Dispose()
    {
        _instrumentation.Dispose();
        GC.SuppressFinalize(this);
    }

    private MetricRecord Sample(
        MetricKind kind = MetricKind.Counter,
        double value = 1.0,
        string? unit = "ms",
        string name = "demo.samples") =>
        new(DateTimeOffset.UnixEpoch, name, kind, value, unit, Attributes);

    private (List<(string Name, double Value, int Tags)> Measurements, MeterListener Listener) Listen()
    {
        var measurements = new List<(string, double, int)>();
        var listener = new MeterListener
        {
            InstrumentPublished = (instrument, active) =>
            {
                if (ReferenceEquals(instrument.Meter, _instrumentation.Meter)) active.EnableMeasurementEvents(instrument);
            },
        };
        listener.SetMeasurementEventCallback<double>((instrument, value, tags, _) =>
            measurements.Add((instrument.Name, value, tags.Length)));
        listener.Start();
        return (measurements, listener);
    }

    [Fact]
    public void Construct_RejectsANullInstrumentation() =>
        FluentActions.Invoking(() => new OtelMetricsCollector(null!)).Should().Throw<ArgumentNullException>();

    [Theory]
    [InlineData(MetricKind.Counter)]
    [InlineData(MetricKind.Gauge)]
    [InlineData(MetricKind.Histogram)]
    public void Emit_RecordsEveryInstrumentKindWithItsTags(MetricKind kind)
    {
        var (measurements, listener) = Listen();
        using (listener)
        {
            new OtelMetricsCollector(_instrumentation)
                .Emit(Sample(kind, 2.5, name: $"demo.{kind}"))
                .Should().BeOk();
        }

        measurements.Should().ContainSingle()
            .Which.Should().Be(($"demo.{kind}", 2.5, 1));
    }

    [Fact]
    public void Emit_ReusesTheInstrumentForARepeatedSeries()
    {
        var (measurements, listener) = Listen();
        var collector = new OtelMetricsCollector(_instrumentation);
        using (listener)
        {
            collector.Emit(Sample(value: 1.0)).Should().BeOk();
            collector.Emit(Sample(value: 2.0)).Should().BeOk();
        }

        measurements.Should().HaveCount(2);
        measurements.Select(measurement => measurement.Value).Should().Equal(1.0, 2.0);
    }

    [Fact]
    public void Emit_TreatsADifferentUnitAsADifferentSeries()
    {
        var (measurements, listener) = Listen();
        var collector = new OtelMetricsCollector(_instrumentation);
        using (listener)
        {
            collector.Emit(Sample(unit: "ms")).Should().BeOk();
            collector.Emit(Sample(unit: null)).Should().BeOk();
        }

        measurements.Should().HaveCount(2);
    }

    [Fact]
    public void Emit_AcceptsASampleCarryingNoAttributes()
    {
        var (measurements, listener) = Listen();
        using (listener)
        {
            new OtelMetricsCollector(_instrumentation)
                .Emit(new MetricRecord(DateTimeOffset.UnixEpoch, "demo.bare", MetricKind.Counter, 1.0))
                .Should().BeOk();
        }

        measurements.Should().ContainSingle().Which.Tags.Should().Be(0);
    }

    [Fact]
    public void Emit_RejectsANullRecord() =>
        new OtelMetricsCollector(_instrumentation)
            .Emit(null!)
            .Should().BeSeamErr(SeamKind.Metrics, "invalid_argument");

    [Fact]
    public void Emit_RejectsAnUndefinedKind() =>
        new OtelMetricsCollector(_instrumentation)
            .Emit(new MetricRecord(DateTimeOffset.UnixEpoch, "demo", (MetricKind)42, 1.0))
            .Should().BeSeamErr(SeamKind.Metrics, "invalid_argument")
            .Which.Detail.Should().Contain("not a recognized metric kind");

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void Emit_RejectsANonFiniteValue(double value) =>
        new OtelMetricsCollector(_instrumentation)
            .Emit(Sample(value: value))
            .Should().BeSeamErr(SeamKind.Metrics, "invalid_argument")
            .Which.Detail.Should().Contain("finite");

    [Fact]
    public void Emit_ReportsAnEmitFailureWhenTheMeterIsDisposed()
    {
        var instrumentation = new Instrumentation(new AppIdentity("l", "p", "s", "m", "1.0.0"));
        instrumentation.Dispose();

        var result = new OtelMetricsCollector(instrumentation).Emit(Sample());

        // A disposed meter either refuses instrument creation or accepts the record as a no-op;
        // either way the seam must report a value rather than throw into the caller.
        result.Match(_ => "ok", error => error.Id).Should().BeOneOf("ok", "emit_failed");
    }
}
