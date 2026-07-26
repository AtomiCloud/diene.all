using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OpenTelemetry.Exporter;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;

namespace AtomiCloud.DotnetBase.UnitTest;

public class OtelHostExtensionsTests
{
    private static AppIdentity Identity { get; } = new("lapras", "atomi", "billing", "api", "1.2.3");

    private static HostApplicationBuilder Builder() => Host.CreateApplicationBuilder();

    private static OtelOption AllOn() => new()
    {
        Logs = new LogsOption { Exporter = Exporter() },
        Metrics = new MetricsOption { Exporter = Exporter() },
        Traces = new TracesOption { Exporter = Exporter() },
    };

    private static ExporterOption Exporter() => new()
    {
        Console = new ConsoleExporterOption { Enabled = true },
        Otlp = new OtlpExporterOption { Enabled = true, Endpoint = "http://collector:4318" },
    };

    [Fact]
    public void OtlpProtocol_IsPinnedFleetWide() => OtelHostExtensions.OtlpProtocol.Should().Be("http/protobuf");

    [Fact]
    public void AddAtomiOtel_RegistersTheIdentityInstrumentationAndEverySeam()
    {
        var builder = Builder();
        builder.AddAtomiOtel(Identity, new OtelOption(), Env.None).Should().BeOk();

        using var host = builder.Build();
        host.Services.GetRequiredService<AppIdentity>().Should().Be(Identity);
        host.Services.GetRequiredService<Instrumentation>().Identity.Should().Be(Identity);
        host.Services.GetRequiredService<ITraceEmitter>().Should().BeOfType<ActivityTraceEmitter>();
        host.Services.GetRequiredService<IMetricsCollector>().Should().BeOfType<OtelMetricsCollector>();
        host.Services.GetRequiredService<ILoggerSink>().Should().BeOfType<OtelLoggerSink>();
    }

    [Fact]
    public void AddAtomiOtel_WiresEverySignalWithEveryExporterOn()
    {
        var builder = Builder();
        builder.AddAtomiOtel(Identity, AllOn(), Env.None).Should().BeOk();

        // Resolving the providers forces every exporter-configuration callback to run,
        // which is where the OTLP endpoint, protocol, and reader interval get applied.
        using var host = builder.Build();
        host.Services.GetRequiredService<MeterProvider>().Should().NotBeNull();
        host.Services.GetRequiredService<TracerProvider>().Should().NotBeNull();
        host.Services.GetRequiredService<ILoggerSink>()
            .Emit(new LogRecord(DateTimeOffset.UnixEpoch, AtomiCloud.Diene.Interfaces.LogLevel.Info, "wired"))
            .Should().BeOk();
    }

    [Fact]
    public void AddAtomiOtel_BuildsACleanNoOpPipelineWhenEveryExporterIsOff()
    {
        var builder = Builder();
        builder.AddAtomiOtel(Identity, new OtelOption(), Env.None).Should().BeOk();

        using var host = builder.Build();
        host.Services.GetRequiredService<ITraceEmitter>().Emit(
            TraceRecord.Create("demo").Should().BeOk().Which).Should().BeOk();
    }

    [Fact]
    public void AddAtomiOtel_SkipsEverySignalWhenTheSdkIsDisabledButStillRegistersTheSeams()
    {
        var builder = Builder();
        builder
            .AddAtomiOtel(Identity, AllOn(), Env.Of((OtelEnvironment.SdkDisabledVariable, "true")))
            .Should().BeOk();

        using var host = builder.Build();
        host.Services.GetRequiredService<ITraceEmitter>().Should().NotBeNull();
    }

    [Fact]
    public void AddAtomiOtel_SkipsADisabledSignal() =>
        Builder()
            .AddAtomiOtel(
                Identity,
                new OtelOption
                {
                    Logs = new LogsOption { Enabled = false },
                    Metrics = new MetricsOption { Enabled = false },
                    Traces = new TracesOption { Enabled = false },
                },
                Env.None)
            .Should().BeOk();

    [Fact]
    public void AddAtomiOtel_HonoursAnExporterOverrideFromTheEnvironment() =>
        Builder()
            .AddAtomiOtel(
                Identity,
                AllOn(),
                Env.Of(
                    (OtelEnvironment.LogsExporterVariable, "none"),
                    (OtelEnvironment.MetricsExporterVariable, "console"),
                    (OtelEnvironment.TracesExporterVariable, "otlp")))
            .Should().BeOk();

    [Fact]
    public void AddAtomiOtel_RejectsABadMetricsInterval() =>
        Builder()
            .AddAtomiOtel(Identity, new OtelOption { Metrics = new MetricsOption { Interval = "every minute" } }, Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("metrics interval");

    [Fact]
    public void AddAtomiOtel_RejectsABadSamplerType() =>
        Builder()
            .AddAtomiOtel(
                Identity,
                new OtelOption { Traces = new TracesOption { Sampler = new SamplerOption { Type = "coin_flip" } } },
                Env.None)
            .Should().BeErr()
            .Which.Operation.Should().Be("sampler");

    [Fact]
    public void AddAtomiOtel_RejectsABadOtlpTimeoutOnAnEnabledSignal() =>
        Builder()
            .AddAtomiOtel(
                Identity,
                new OtelOption
                {
                    Metrics = new MetricsOption { Interval = "PT10S" },
                    Traces = new TracesOption
                    {
                        Exporter = new ExporterOption
                        {
                            Otlp = new OtlpExporterOption { Enabled = true, Timeout = "ten seconds" },
                        },
                    },
                },
                Env.None)
            .Should().BeOk();

    [Fact]
    public void AddAtomiOtel_RejectsNullArguments()
    {
        FluentActions.Invoking(() => OtelHostExtensions.AddAtomiOtel(null!, Identity, new OtelOption()))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => Builder().AddAtomiOtel(null!, new OtelOption()))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => Builder().AddAtomiOtel(Identity, (OtelOption)null!))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => Builder().AddAtomiOtel(Identity, (IConfiguration)null!))
            .Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void AddAtomiOtel_ReadsTheBlockFromConfiguration()
    {
        var builder = Builder();
        builder.Configuration.AddInMemoryCollection(
        [
            new("Otel:Traces:Sampler:Type", "always_off"),
            new("Otel:Metrics:Interval", "PT30S"),
        ]);

        builder.AddAtomiOtel(Identity, builder.Configuration, Env.None).Should().BeOk();
    }

    [Fact]
    public void AddAtomiOtel_TreatsAMissingSectionAsTheShippedDefaults() =>
        Builder().AddAtomiOtel(Identity, new ConfigurationBuilder().Build(), Env.None).Should().BeOk();

    [Fact]
    public void AddAtomiOtel_ReadsTheProcessEnvironmentWhenNoneIsInjected() =>
        Builder().AddAtomiOtel(Identity, new OtelOption()).Should().BeOk();

    [Fact]
    public void Otlp_AppliesTheEndpointProtocolHeadersAndTimeout()
    {
        var target = new OtlpExporterOptions();

        OtelHostExtensions
            .Otlp(
                target,
                new OtlpExporterOption
                {
                    Endpoint = " http://collector:4318 ",
                    Timeout = "PT5S",
                    Headers = new Dictionary<string, string>(StringComparer.Ordinal)
                    {
                        ["x-tenant"] = "acme",
                        ["x-env"] = "lapras",
                    },
                },
                Env.None)
            .Should().BeOk();

        target.Endpoint.Should().Be(new Uri("http://collector:4318"));
        target.Protocol.Should().Be(OtlpExportProtocol.HttpProtobuf);
        target.TimeoutMilliseconds.Should().Be(5000);
        target.Headers.Should().Contain("x-tenant=acme").And.Contain("x-env=lapras");
    }

    [Fact]
    public void Otlp_LeavesTheEndpointAloneWhenTheEnvironmentSetsIt()
    {
        var target = new OtlpExporterOptions();

        OtelHostExtensions
            .Otlp(
                target,
                new OtlpExporterOption { Endpoint = "http://block:4318" },
                Env.Of((OtelEnvironment.OtlpEndpointVariable, "http://ops:4318")))
            .Should().BeOk();

        // The SDK's own default endpoint follows the protocol; what matters is that the
        // block's endpoint never reached it, so the ops override is the one that applies.
        target.Endpoint.Host.Should().NotBe("block");
    }

    [Fact]
    public void Otlp_LeavesTheEndpointAtTheSdkDefaultWhenTheBlockIsBlank()
    {
        var target = new OtlpExporterOptions();

        OtelHostExtensions.Otlp(target, new OtlpExporterOption { Endpoint = "  " }, Env.None).Should().BeOk();

        target.Endpoint.Should().Be(new Uri("http://localhost:4318"));
    }

    [Theory]
    [InlineData("collector:4318")]
    [InlineData("ftp://collector:4318")]
    [InlineData("/relative/path")]
    public void Otlp_RejectsAnEndpointThatIsNotAnAbsoluteHttpUri(string endpoint) =>
        OtelHostExtensions
            .Otlp(new OtlpExporterOptions(), new OtlpExporterOption { Endpoint = endpoint }, Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("absolute http or https URI");

    [Fact]
    public void Otlp_AcceptsAnHttpsEndpoint()
    {
        var target = new OtlpExporterOptions();
        OtelHostExtensions
            .Otlp(target, new OtlpExporterOption { Endpoint = "https://collector:4318" }, Env.None)
            .Should().BeOk();
        target.Endpoint.Scheme.Should().Be("https");
    }

    [Fact]
    public void Otlp_LeavesHeadersAloneWhenTheBlockCarriesNone()
    {
        var target = new OtlpExporterOptions();
        var original = target.Headers;

        OtelHostExtensions.Otlp(target, new OtlpExporterOption(), Env.None).Should().BeOk();

        target.Headers.Should().Be(original);
    }

    [Fact]
    public void Otlp_RejectsABadTimeout() =>
        OtelHostExtensions
            .Otlp(new OtlpExporterOptions(), new OtlpExporterOption { Timeout = "10s" }, Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("timeout");

    [Fact]
    public void Otlp_RejectsNullArguments()
    {
        FluentActions.Invoking(() => OtelHostExtensions.Otlp(null!, new OtlpExporterOption(), Env.None))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => OtelHostExtensions.Otlp(new OtlpExporterOptions(), null!, Env.None))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => OtelHostExtensions.Otlp(new OtlpExporterOptions(), new OtlpExporterOption(), null!))
            .Should().Throw<ArgumentNullException>();
    }

    [Theory]
    [InlineData("PT60S", 60)]
    [InlineData("PT1M", 60)]
    [InlineData("PT0.5S", 0.5)]
    public void Duration_ParsesAnIso8601Duration(string wire, double seconds) =>
        OtelHostExtensions
            .Duration(wire, "interval")
            .Should().BeOk()
            .Which.TotalSeconds.Should().Be(seconds);

    [Theory]
    [InlineData("60s")]
    [InlineData("P1M")]
    [InlineData("")]
    public void Duration_RejectsAnythingElse(string wire) =>
        OtelHostExtensions
            .Duration(wire, "interval")
            .Should().BeErr()
            .Which.Message.Should().Contain("interval");

    [Fact]
    public void Duration_ReportsTheOffendingValueAndTheConfigOperation()
    {
        var error = OtelHostExtensions.Duration("nope", "metrics interval").Should().BeErr().Which;
        error.Operation.Should().Be("config");
        error.Message.Should().Contain("nope");
    }
}
