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

    /// <summary>A block whose named signal carries one deliberately invalid OTLP exporter.</summary>
    private static OtelOption WithOtlp(string signal, OtlpExporterOption otlp)
    {
        var exporter = new ExporterOption { Otlp = otlp };
        return new OtelOption
        {
            Logs = new LogsOption { Exporter = signal == "logs" ? exporter : new ExporterOption() },
            Metrics = new MetricsOption { Exporter = signal == "metrics" ? exporter : new ExporterOption() },
            Traces = new TracesOption { Exporter = signal == "traces" ? exporter : new ExporterOption() },
        };
    }

    private static OtlpExporterOption Enabled(string endpoint = "http://collector:4318", string timeout = "PT10S") =>
        new() { Enabled = true, Endpoint = endpoint, Timeout = timeout };

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

    [Theory]
    [InlineData("logs")]
    [InlineData("metrics")]
    [InlineData("traces")]
    public void AddAtomiOtel_RejectsABadOtlpTimeoutOnEverySignal(string signal) =>
        Builder()
            .AddAtomiOtel(Identity, WithOtlp(signal, Enabled(timeout: "ten seconds")), Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("timeout");

    [Theory]
    [InlineData("logs")]
    [InlineData("metrics")]
    [InlineData("traces")]
    public void AddAtomiOtel_RejectsABlankEndpointOnAnEnabledOtlpExporter(string signal) =>
        Builder()
            .AddAtomiOtel(Identity, WithOtlp(signal, Enabled(endpoint: "  ")), Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("needs an endpoint");

    [Theory]
    [InlineData("logs", "http://collector:4317")]
    [InlineData("metrics", "http://collector:4317")]
    [InlineData("traces", "http://collector:4317")]
    [InlineData("logs", "http://collector")]
    [InlineData("metrics", "https://collector")]
    [InlineData("traces", "http://collector:8080")]
    public void AddAtomiOtel_RejectsAnEndpointThatIsNotTheFleetPort(string signal, string endpoint) =>
        Builder()
            .AddAtomiOtel(Identity, WithOtlp(signal, Enabled(endpoint)), Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain($":{OtelHostExtensions.OtlpPort}");

    [Theory]
    [InlineData("logs")]
    [InlineData("metrics")]
    [InlineData("traces")]
    public void AddAtomiOtel_AcceptsABlankEndpointWhenTheEnvironmentSuppliesOne(string signal) =>
        Builder()
            .AddAtomiOtel(
                Identity,
                WithOtlp(signal, Enabled(endpoint: "")),
                Env.Of((OtelEnvironment.OtlpEndpointVariable, "http://ops:4318")))
            .Should().BeOk();

    [Theory]
    [InlineData("logs")]
    [InlineData("metrics")]
    [InlineData("traces")]
    public void AddAtomiOtel_IgnoresAnInvalidOtlpBlockWhenThatExporterIsNotSelected(string signal) =>
        Builder()
            .AddAtomiOtel(
                Identity,
                WithOtlp(signal, new OtlpExporterOption { Enabled = false, Timeout = "ten seconds" }),
                Env.None)
            .Should().BeOk();

    [Theory]
    [InlineData("logs")]
    [InlineData("metrics")]
    [InlineData("traces")]
    public void AddAtomiOtel_RejectsANonFleetProtocolOnAnEnabledOtlpExporter(string signal) =>
        Builder()
            .AddAtomiOtel(
                Identity,
                WithOtlp(signal, new OtlpExporterOption { Enabled = true, Endpoint = "http://c:4318", Protocol = "grpc" }),
                Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("pinned");

    [Fact]
    public void AddAtomiOtel_RejectsAnInvalidExporterSelectedOnlyByTheEnvironment() =>
        Builder()
            .AddAtomiOtel(
                Identity,
                WithOtlp("traces", new OtlpExporterOption { Enabled = false, Endpoint = "http://c:4317" }),
                Env.Of((OtelEnvironment.TracesExporterVariable, "otlp")))
            .Should().BeErr();

    [Fact]
    public void AddAtomiOtel_LeavesTheHostUntouchedWhenALaterSignalFails()
    {
        // Plan-then-register: a valid logs block ahead of an invalid traces block must not
        // leave a half-wired pipeline on a host whose startup then fails.
        var builder = Builder();
        var option = WithOtlp("traces", Enabled("http://collector:4317"));
        option.Logs.Exporter.Otlp = Enabled();

        builder.AddAtomiOtel(Identity, option, Env.None).Should().BeErr();

        using var host = builder.Build();
        host.Services.GetService<TracerProvider>().Should().BeNull();
        host.Services.GetService<MeterProvider>().Should().BeNull();
        host.Services.GetService<ITraceEmitter>().Should().BeNull("no seam is registered when planning fails");
        host.Services.GetService<Instrumentation>().Should().BeNull();
    }

    [Fact]
    public void AddAtomiOtel_RegistersEverySignalWhenTheWholePlanIsValid()
    {
        var builder = Builder();
        builder.AddAtomiOtel(Identity, AllOn(), Env.None).Should().BeOk();

        using var host = builder.Build();
        host.Services.GetService<TracerProvider>().Should().NotBeNull();
        host.Services.GetService<MeterProvider>().Should().NotBeNull();
    }

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
    public void OtlpPort_IsTheFleetHttpPort() => OtelHostExtensions.OtlpPort.Should().Be(4318);

    [Fact]
    public void Preflight_ValidatesTheEndpointHeadersAndTimeout()
    {
        var settings = OtelHostExtensions
            .Preflight(
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
            .Should().BeOk().Which;

        settings.Endpoint.Should().BeSome().Which.Should().Be(new Uri("http://collector:4318"));
        settings.TimeoutMilliseconds.Should().Be(5000);
        settings.Headers.Should().BeSome().Which.Should().Contain("x-tenant=acme").And.Contain("x-env=lapras");
    }

    [Theory]
    [InlineData("PT0S")]
    [InlineData("P0D")]
    [InlineData("-PT1S")]
    [InlineData("P30D")]
    public void Preflight_RejectsATimeoutOutsideTheUsableMillisecondRange(string timeout) =>
        OtelHostExtensions
            .Preflight(Enabled(timeout: timeout), Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("between 1ms");

    [Theory]
    [InlineData("PT0.001S", 1)]
    [InlineData("PT10S", 10_000)]
    public void Preflight_AcceptsATimeoutAtTheEdgeOfTheUsableRange(string timeout, int expected) =>
        OtelHostExtensions
            .Preflight(Enabled(timeout: timeout), Env.None)
            .Should().BeOk()
            .Which.TimeoutMilliseconds.Should().Be(expected);

    [Theory]
    [InlineData("PT0S")]
    [InlineData("-PT1S")]
    [InlineData("P30D")]
    public void AddAtomiOtel_RejectsAMetricsIntervalOutsideTheUsableRange(string interval) =>
        Builder()
            .AddAtomiOtel(Identity, new OtelOption { Metrics = new MetricsOption { Interval = interval } }, Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("metrics interval");

    [Theory]
    [InlineData("PT0.001S", 1)]
    [InlineData("PT1M", 60_000)]
    public void Milliseconds_ReducesAValidDurationToWholeMilliseconds(string value, int expected) =>
        OtelHostExtensions.Milliseconds(value, "interval").Should().BeOk().Which.Should().Be(expected);

    [Fact]
    public void Milliseconds_PropagatesAParseFailure() =>
        OtelHostExtensions
            .Milliseconds("60s", "interval")
            .Should().BeErr()
            .Which.Message.Should().Contain("ISO 8601");

    [Fact]
    public void Milliseconds_RejectsADurationBeyondIntRange() =>
        OtelHostExtensions
            .Milliseconds("P25D", "interval")
            .Should().BeErr()
            .Which.Message.Should().Contain($"{int.MaxValue}ms");

    [Fact]
    public void Apply_WritesOnlyPrevalidatedSettingsOntoTheExporter()
    {
        var settings = OtelHostExtensions
            .Preflight(Enabled("https://collector:4318", "PT5S"), Env.None)
            .Should().BeOk().Which;
        var target = new OtlpExporterOptions();

        OtelHostExtensions.Apply(target, settings);

        target.Endpoint.Should().Be(new Uri("https://collector:4318"));
        target.Protocol.Should().Be(OtlpExportProtocol.HttpProtobuf);
        target.TimeoutMilliseconds.Should().Be(5000);
    }

    [Fact]
    public void Apply_WritesTheHeadersWhenTheBlockCarriesThem()
    {
        var configured = Enabled();
        configured.Headers = new Dictionary<string, string>(StringComparer.Ordinal) { ["x-tenant"] = "acme" };
        var settings = OtelHostExtensions.Preflight(configured, Env.None).Should().BeOk().Which;
        var target = new OtlpExporterOptions();

        OtelHostExtensions.Apply(target, settings);

        target.Headers.Should().Contain("x-tenant=acme");
    }

    [Fact]
    public void Apply_LeavesTheEndpointAndHeadersAtTheSdkDefaultWhenThePreflightYieldedNone()
    {
        var settings = OtelHostExtensions
            .Preflight(Enabled(endpoint: ""), Env.Of((OtelEnvironment.OtlpEndpointVariable, "http://ops:4318")))
            .Should().BeOk().Which;
        var target = new OtlpExporterOptions();
        var headers = target.Headers;

        OtelHostExtensions.Apply(target, settings);

        // The env override owns the endpoint, so the block must not have written one.
        settings.Endpoint.Should().BeNone();
        target.Endpoint.Host.Should().NotBe("ops");
        target.Headers.Should().Be(headers);
    }

    [Fact]
    public void Apply_RejectsANullTarget()
    {
        var settings = OtelHostExtensions.Preflight(Enabled(), Env.None).Should().BeOk().Which;
        FluentActions.Invoking(() => OtelHostExtensions.Apply(null!, settings))
            .Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Preflight_RejectsABlankEndpointWhenNoEnvironmentOverrideExists() =>
        OtelHostExtensions
            .Preflight(Enabled(endpoint: "   "), Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("needs an endpoint");

    [Theory]
    [InlineData("collector:4318")]
    [InlineData("ftp://collector:4318")]
    [InlineData("/relative/path")]
    public void Preflight_RejectsAnEndpointThatIsNotAnAbsoluteHttpUri(string endpoint) =>
        OtelHostExtensions
            .Preflight(Enabled(endpoint), Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("absolute http or https URI");

    [Theory]
    [InlineData("http://collector:4317")]
    [InlineData("http://collector")]
    [InlineData("https://collector")]
    [InlineData("http://collector:8080")]
    public void Preflight_RejectsAnyPortOtherThanTheExplicitFleetPort(string endpoint) =>
        OtelHostExtensions
            .Preflight(Enabled(endpoint), Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain(":4318");

    [Fact]
    public void Preflight_AcceptsAnHttpsFleetPortEndpoint() =>
        OtelHostExtensions
            .Preflight(Enabled("https://collector:4318"), Env.None)
            .Should().BeOk()
            .Which.Endpoint.Should().BeSome()
            .Which.Scheme.Should().Be("https");

    [Fact]
    public void Preflight_YieldsNoHeadersWhenTheBlockCarriesNone() =>
        OtelHostExtensions
            .Preflight(Enabled(), Env.None)
            .Should().BeOk()
            .Which.Headers.Should().BeNone();

    [Fact]
    public void Preflight_RejectsABadTimeout() =>
        OtelHostExtensions
            .Preflight(Enabled(timeout: "10s"), Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("timeout");

    [Fact]
    public void Preflight_RejectsANonFleetProtocol() =>
        OtelHostExtensions
            .Preflight(
                new OtlpExporterOption { Enabled = true, Endpoint = "http://c:4318", Protocol = "grpc" },
                Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("pinned");

    [Fact]
    public void Preflight_RejectsNullArguments()
    {
        FluentActions.Invoking(() => OtelHostExtensions.Preflight(null!, Env.None))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => OtelHostExtensions.Preflight(new OtlpExporterOption(), null!))
            .Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Preflight_TreatsNullBlockFieldsAsRejectionsRatherThanThrowing()
    {
        // Every field is bound from external configuration, so a null must come back as a
        // value. A NullReferenceException out of a wiring call would be a totality break.
        var noHeaders = Enabled();
        noHeaders.Headers = null!;
        OtelHostExtensions.Preflight(noHeaders, Env.None).Should().BeOk().Which.Headers.Should().BeNone();

        var noTimeout = Enabled();
        noTimeout.Timeout = null!;
        OtelHostExtensions
            .Preflight(noTimeout, Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("absent");

        var noProtocol = Enabled();
        noProtocol.Protocol = null!;
        OtelHostExtensions
            .Preflight(noProtocol, Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("pinned");

        var noEndpoint = Enabled();
        noEndpoint.Endpoint = null!;
        OtelHostExtensions
            .Preflight(noEndpoint, Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("needs an endpoint");
    }

    [Fact]
    public void Duration_TreatsAnAbsentValueAsARejection() =>
        OtelHostExtensions
            .Duration(null, "interval")
            .Should().BeErr()
            .Which.Message.Should().Contain("absent");

    [Fact]
    public void Apply_RejectsNullSettings() =>
        FluentActions.Invoking(() => OtelHostExtensions.Apply(new OtlpExporterOptions(), null!))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void OtlpSettings_CanOnlyBeProducedByPreflight()
    {
        // The type IS the proof of validation: if a caller could construct one, Apply's
        // "already validated" guarantee would be worth nothing.
        var type = typeof(OtelHostExtensions.OtlpSettings);

        type.GetConstructors().Should().BeEmpty("no public constructor may exist");
        type.GetProperties().Should().AllSatisfy(property =>
            property.CanWrite.Should().BeFalse($"'{property.Name}' must be get-only"));
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
