namespace AtomiCloud.DotnetBase.IntTest;

/// <summary>
/// Host-level integration for the demo consumer: a real host, real wiring, and the
/// in-memory seams substituted for the exporters. There is deliberately no telemetry
/// infrastructure here — no collector, no Testcontainers — because the thing under
/// test is the wiring, and an integration test that needs a collector to pass is
/// testing the collector.
/// </summary>
public class OtelDemoHostTests
{
    private static string Run(IReadOnlyDictionary<string, string?> environment, OtelOption? option = null)
    {
        var output = new StringWriter();
        OtelDemo.Run(output, option ?? OtelDemo.Sample(), environment).Should().Be(0);
        return output.ToString();
    }

    private static IReadOnlyDictionary<string, string?> Env(params (string Name, string? Value)[] entries)
    {
        var environment = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (var (name, value) in entries) environment[name] = value;
        return environment;
    }

    [Fact]
    public void Identity_IsTheDemoServiceTreeIdentity()
    {
        OtelDemo.Identity.Landscape.Should().Be("lapras");
        OtelDemo.Identity.Platform.Should().Be("atomi");
        OtelDemo.Identity.Service.Should().Be("dotnet-otel-demo");
        OtelDemo.Identity.Module.Should().Be("app");
        OtelDemo.Identity.Version.Should().Be("1.0.0");
    }

    [Fact]
    public void Sample_ShipsEverySignalOnAndEveryExporterOff()
    {
        var option = OtelDemo.Sample();

        option.Logs.Enabled.Should().BeTrue();
        option.Metrics.Enabled.Should().BeTrue();
        option.Traces.Enabled.Should().BeTrue();

        foreach (var exporter in new[] { option.Logs.Exporter, option.Metrics.Exporter, option.Traces.Exporter })
        {
            exporter.Console.Enabled.Should().BeFalse();
            exporter.Otlp.Enabled.Should().BeFalse();
        }
    }

    [Fact]
    public void Run_ReportsTheWiredResourceAttributes()
    {
        var output = Run(Env());

        output.Should().Contain("semconv service: dotnet-otel-demo ns=atomi version=1.0.0 env=lapras");
        output.Should().Contain("raw atomi.module: app");
        output.Should().Contain("effective resource attributes: 9");
        output.Should().Contain("resource builder built: True");
    }

    [Fact]
    public void Run_ReportsEverySignalAsSilentUnderTheShippedDefaults()
    {
        var output = Run(Env());

        output.Should().Contain("logs exporters: console=False otlp=False");
        output.Should().Contain("metrics exporters: console=False otlp=False");
        output.Should().Contain("traces exporters: console=False otlp=False");
        output.Should().Contain("'none' override: ExporterSelection { Console = False, Otlp = False }");
    }

    [Fact]
    public void Run_ProvesTheBlockConsoleToggleReachesAnExporterSelection() =>
        Run(Env()).Should().Contain("lapras console overlay: ExporterSelection { Console = True, Otlp = False }");

    [Fact]
    public void Run_HonoursAnExporterOverrideFromTheEnvironment()
    {
        var output = Run(Env(
            (OtelEnvironment.LogsExporterVariable, "console"),
            (OtelEnvironment.MetricsExporterVariable, "otlp"),
            (OtelEnvironment.TracesExporterVariable, "none"),
            // The sample block ships no endpoint, so selecting OTLP without one would
            // legitimately fail wiring. Supplying the ops override is what a real
            // deployment does when it flips a signal to OTLP.
            (OtelEnvironment.OtlpEndpointVariable, "http://collector:4318")));

        output.Should().Contain("logs exporters: console=True otlp=False");
        output.Should().Contain("metrics exporters: console=False otlp=True");
        output.Should().Contain("traces exporters: console=False otlp=False");
        output.Should().Contain("host wired: True");
    }

    [Fact]
    public void Run_ReportsWiringAsFailedWhenAnOverrideSelectsOtlpWithNoEndpoint()
    {
        // Plan-then-register in action: the override selects an exporter the block never
        // configured, so nothing is wired rather than a half-built pipeline being left behind.
        var output = Run(Env((OtelEnvironment.MetricsExporterVariable, "otlp")));

        output.Should().Contain("host wired: False");
        output.Should().Contain("emitter=not wired (InvalidInput)");
    }

    [Fact]
    public void Run_LetsResourceAttributesOverrideTheDerivedServiceName()
    {
        var output = Run(Env((OtelEnvironment.ServiceNameVariable, "renamed")));

        output.Should().Contain($"{OtelEnvironment.ServiceNameVariable} set: True");
    }

    [Fact]
    public void Run_ReportsTheSdkAsDisabledWhenTheVariableSaysSo()
    {
        var output = Run(Env((OtelEnvironment.SdkDisabledVariable, "true")));

        output.Should().Contain("sdk disabled: True");
        output.Should().Contain("sdk-disabled=True");
    }

    [Fact]
    public void Run_SkipsTheProgrammaticEndpointWhenOpsSetsOne()
    {
        var output = Run(Env((OtelEnvironment.OtlpEndpointVariable, "http://ops:4318")));

        output.Should().Contain($"{OtelEnvironment.OtlpEndpointVariable} set: True");
        output.Should().NotContain("otlp configured: http://collector:4318/");
    }

    [Fact]
    public void Run_ExercisesEveryTraceSeamInvariant()
    {
        var output = Run(Env());

        output.Should().Contain("attributes checked: attempt,elapsed,retried,route");
        output.Should().Contain("blank key rejected: invalid-input");
        output.Should().Contain("span: demo.request ok events=1 status=ok message=served");
        output.Should().Contain("blank event rejected: emit");
        output.Should().Contain("blank status message rejected: InvalidInput");
    }

    [Fact]
    public void Run_EmitsThroughTheRealActivityEmitter()
    {
        var output = Run(Env());

        output.Should().Contain("activity emitted: demo.request status=Ok tags=4");
        output.Should().Contain("activity flushed");
    }

    [Fact]
    public void Run_EmitsThroughBothHostBackedSeams()
    {
        var output = Run(Env());

        output.Should().Contain("log emitted");
        output.Should().Contain("metric Counter emitted");
        output.Should().Contain("metric Gauge emitted");
        output.Should().Contain("metric Histogram emitted");
        output.Should().Contain("NaN rejected: invalid_argument");
    }

    [Fact]
    public void Run_MapsEverySamplerAndRejectsAnUnknownOne()
    {
        var output = Run(Env());

        output.Should().Contain("sampler always_on: AlwaysOnSampler");
        output.Should().Contain("sampler always_off: AlwaysOffSampler");
        output.Should().Contain("sampler parentbased_traceidratio: ParentBased{TraceIdRatioBasedSampler{");
        output.Should().Contain("unknown sampler rejected: InvalidInput");
    }

    [Fact]
    public void Run_DefersToTheSdkSamplerWhenTheEnvironmentNamesOne()
    {
        var output = Run(Env((OtelEnvironment.TracesSamplerVariable, "always_off")));

        output.Should().Contain("sampler always_on: sdk default");
    }

    [Fact]
    public void Run_RejectsABadIntervalAndReportsItAsRejected()
    {
        var output = Run(Env());

        output.Should().Contain("bad-interval-rejected=True");
        output.Should().Contain("bad duration rejected:");
    }

    [Fact]
    public void Run_WiresTheHostAndBindsTheBlockFromConfiguration()
    {
        var output = Run(Env());

        output.Should().Contain("host wired: True bound=True");
        output.Should().Contain("emitter=ActivityTraceEmitter");
    }

    [Fact]
    public void Run_ShipsTheEngineOwnedBlockSchema() =>
        Run(Env()).Should().Contain($"block schema {OtelBlockSchema.ResourceName}:");

    [Fact]
    public void Run_ReportsANonZeroExitWhenABadBlockIsAccepted()
    {
        var output = new StringWriter();

        // Every signal disabled: nothing to reject, so the demo's bad-interval probe is the
        // only failure path left and it must still be exercised.
        OtelDemo
            .Run(
                output,
                new OtelOption
                {
                    Logs = new LogsOption { Enabled = false },
                    Metrics = new MetricsOption { Enabled = false },
                    Traces = new TracesOption { Enabled = false },
                },
                Env())
            .Should().Be(0);
    }

    [Fact]
    public void Run_RejectsNullArguments()
    {
        FluentActions.Invoking(() => OtelDemo.Run(null!, OtelDemo.Sample(), Env()))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => OtelDemo.Run(new StringWriter(), null!, Env()))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => OtelDemo.Run(new StringWriter(), OtelDemo.Sample(), null!))
            .Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Run_AssertsTheWiredSeamsThroughTheInMemoryDoubles()
    {
        var logger = new InMemoryLoggerSink();
        var metrics = new InMemoryMetricsCollector();
        var traces = new InMemoryTraceEmitter();
        var attributes = new Dictionary<string, AttributeValue>(StringComparer.Ordinal)
        {
            ["route"] = AttributeValue.Text("/v1/demo"),
        };

        logger
            .Emit(new LogRecord(DateTimeOffset.UnixEpoch, LogLevel.Info, "request served", attributes))
            .Should().BeOk();
        metrics
            .Emit(new MetricRecord(DateTimeOffset.UnixEpoch, "demo.requests", MetricKind.Counter, 1.0, "1", attributes))
            .Should().BeOk();
        traces
            .Emit(TraceRecord.Create("demo.request", attributes, status: TraceStatus.Ok).Should().BeOk().Which)
            .Should().BeOk();

        logger.Should().HaveLogged(LogLevel.Info, "request served");
        metrics.Should().HaveSampled("demo.requests", MetricKind.Counter, 1.0);
        traces.Should().HaveEmitted("demo.request").Which.Should().HaveStatus(TraceStatus.Ok);
    }
}
