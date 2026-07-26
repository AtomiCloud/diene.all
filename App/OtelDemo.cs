using System.Diagnostics;
using System.Globalization;
using AtomiCloud.Diene.Interfaces;
using AtomiCloud.Diene.Otel;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// The demo consumer. It wires the otel engine onto a real host with every exporter
/// OFF — the default a service ships with — and then drives each public entry point
/// on its output path, so the surface this package publishes is the surface that is
/// proven to work end to end.
/// </summary>
public static class OtelDemo
{
    /// <summary>An environment with no overrides, for probing block-only behaviour.</summary>
    private static IReadOnlyDictionary<string, string?> Environment_Empty { get; } =
        new Dictionary<string, string?>(StringComparer.Ordinal);

    /// <summary>The identity the demo reports telemetry under.</summary>
    public static AppIdentity Identity { get; } = AppIdentity
        .Create("lapras", "atomi", "dotnet-otel-demo", "app", "1.0.0")
        .GetOr(new AppIdentity("lapras", "atomi", "dotnet-otel-demo", "app", "1.0.0"));

    /// <summary>
    /// The sample block: exactly the shipped defaults. Console and OTLP are both off,
    /// which is the point — a service that forgets to configure an overlay emits
    /// nothing rather than spraying spans at stdout in production.
    /// </summary>
    public static OtelOption Sample() => new()
    {
        Logs = new LogsOption { Enabled = true },
        Metrics = new MetricsOption { Enabled = true, Interval = "PT60S" },
        Traces = new TracesOption
        {
            Enabled = true,
            Sampler = new SamplerOption { Type = OtelSampler.ParentBasedTraceIdRatio, Ratio = 1.0 },
        },
    };

    /// <summary>Runs the demo, returning a process exit code.</summary>
    /// <param name="output">Where the demo reports what it observed.</param>
    /// <param name="option">The block to wire.</param>
    /// <param name="environment">The environment overrides to resolve against.</param>
    public static int Run(TextWriter output, OtelOption option, IReadOnlyDictionary<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(output);
        ArgumentNullException.ThrowIfNull(option);
        ArgumentNullException.ThrowIfNull(environment);

        Identity_(output);
        Resource(output, environment);
        Environment_(output, option, environment);
        Schema(output);
        Sampler(output, option, environment);
        Exporter(output, option, environment);
        Traces(output);
        return Host(output, option, environment);
    }

    private static void Identity_(TextWriter output)
    {
        output.WriteLine($"identity: {Identity.Landscape}/{Identity.Platform}/{Identity.Service}"
            + $"/{Identity.Module}/{Identity.Version}");
        AppIdentity
            .Create(" ", "atomi", "svc", "app", "1.0.0")
            .Match(
                identity => output.WriteLine($"identity accepted a blank landscape: {identity}"),
                error => output.WriteLine($"identity rejected: {error.Id}"));
    }

    private static void Resource(TextWriter output, IReadOnlyDictionary<string, string?> environment)
    {
        var mapped = AtomiResource.Map(Identity);
        output.WriteLine($"semconv service: {mapped[AtomiResource.ServiceNameKey]}"
            + $" ns={mapped[AtomiResource.ServiceNamespaceKey]}"
            + $" version={mapped[AtomiResource.ServiceVersionKey]}"
            + $" env={mapped[AtomiResource.DeploymentEnvironmentNameKey]}");
        output.WriteLine($"raw atomi.module: {mapped["atomi.module"]}");

        var parsed = AtomiResource.ParseResourceAttributes("tenant=acme, =dropped, malformed");
        output.WriteLine($"OTEL_RESOURCE_ATTRIBUTES parsed {parsed.Count} entry(s): "
            + string.Join(",", parsed.Select(entry => $"{entry.Key}={entry.Value}")));

        var effective = AtomiResource.Attributes(Identity, environment);
        output.WriteLine($"effective resource attributes: {effective.Count}");
        output.WriteLine($"resource builder built: {AtomiResource.Build(Identity, environment) is not null}");
    }

    private static void Environment_(
        TextWriter output,
        OtelOption option,
        IReadOnlyDictionary<string, string?> environment)
    {
        output.WriteLine($"sdk disabled: {OtelEnvironment.IsSdkDisabled(environment)}");
        output.WriteLine($"{OtelEnvironment.OtlpEndpointVariable} set: "
            + $"{OtelEnvironment.HasValue(environment, OtelEnvironment.OtlpEndpointVariable)}");
        output.WriteLine($"{OtelEnvironment.ServiceNameVariable} set: "
            + $"{OtelEnvironment.HasValue(environment, OtelEnvironment.ServiceNameVariable)}");
        output.WriteLine($"{OtelEnvironment.ResourceAttributesVariable} set: "
            + $"{OtelEnvironment.HasValue(environment, OtelEnvironment.ResourceAttributesVariable)}");
        output.WriteLine($"{OtelEnvironment.TracesSamplerVariable} set: "
            + $"{OtelEnvironment.HasValue(environment, OtelEnvironment.TracesSamplerVariable)}");
        output.WriteLine($"{OtelEnvironment.SdkDisabledVariable} set: "
            + $"{OtelEnvironment.HasValue(environment, OtelEnvironment.SdkDisabledVariable)}");

        foreach (var (label, variable, exporter) in new[]
        {
            ("logs", OtelEnvironment.LogsExporterVariable, option.Logs.Exporter),
            ("metrics", OtelEnvironment.MetricsExporterVariable, option.Metrics.Exporter),
            ("traces", OtelEnvironment.TracesExporterVariable, option.Traces.Exporter),
        })
        {
            var selection = OtelEnvironment.Exporters(exporter, variable, environment);
            output.WriteLine($"{label} exporters: console={selection.Console} otlp={selection.Otlp}");
        }

        var silenced = OtelEnvironment.Exporters(
            option.Traces.Exporter,
            OtelEnvironment.TracesExporterVariable,
            new Dictionary<string, string?>(StringComparer.Ordinal)
            {
                [OtelEnvironment.TracesExporterVariable] = "none",
            });
        output.WriteLine($"'none' override: {silenced}");

        // The lapras overlay is the only place console output is turned on; exercising it
        // here proves the block's console toggle actually reaches an exporter selection.
        var overlay = OtelEnvironment.Exporters(
            new ExporterOption { Console = new ConsoleExporterOption { Enabled = true } },
            OtelEnvironment.LogsExporterVariable,
            Environment_Empty);
        output.WriteLine($"lapras console overlay: {overlay}");
    }

    private static void Schema(TextWriter output) =>
        output.WriteLine($"block schema {OtelBlockSchema.ResourceName}: {OtelBlockSchema.Json.Length} chars");

    private static void Sampler(
        TextWriter output,
        OtelOption option,
        IReadOnlyDictionary<string, string?> environment)
    {
        foreach (var type in new[] { OtelSampler.AlwaysOn, OtelSampler.AlwaysOff, OtelSampler.ParentBasedTraceIdRatio })
        {
            OtelSampler
                .Create(new SamplerOption { Type = type, Ratio = option.Traces.Sampler.Ratio }, environment)
                .Match(
                    sampler => output.WriteLine($"sampler {type}: "
                        + $"{sampler.Match(selected => selected.Description, () => "sdk default")}"),
                    error => output.WriteLine($"sampler {type} rejected: {error}"));
        }

        OtelSampler
            .Create(new SamplerOption { Type = "coin_flip" }, environment)
            .Match(
                _ => output.WriteLine("sampler accepted an unknown type"),
                error => output.WriteLine($"unknown sampler rejected: {error.Code}"));
    }

    private static void Exporter(
        TextWriter output,
        OtelOption option,
        IReadOnlyDictionary<string, string?> environment)
    {
        output.WriteLine($"otlp protocol pinned to {OtelHostExtensions.OtlpProtocol}:"
            + $" block says {option.Traces.Exporter.Otlp.Protocol}");

        output.WriteLine($"otlp fleet port pinned to {OtelHostExtensions.OtlpPort}");

        var target = new OpenTelemetry.Exporter.OtlpExporterOptions();
        var configured = new OtlpExporterOption
        {
            Enabled = true,
            Endpoint = "http://collector:4318",
            Headers = new Dictionary<string, string>(StringComparer.Ordinal) { ["x-tenant"] = "acme" },
            Timeout = "PT10S",
        };
        OtelHostExtensions
            .Preflight(configured, environment)
            .Match(
                settings =>
                {
                    OtelHostExtensions.Apply(target, settings);
                    output.WriteLine($"otlp configured: {target.Endpoint} {target.Protocol}"
                        + $" timeout={target.TimeoutMilliseconds}ms headers={target.Headers}");
                },
                error => output.WriteLine($"otlp rejected: {error}"));

        foreach (var (label, bad) in new[]
        {
            ("relative endpoint", "collector:4318"),
            ("wrong port", "http://collector:4317"),
            ("implicit port", "http://collector"),
            ("blank endpoint", "   "),
        })
        {
            OtelHostExtensions
                .Preflight(new OtlpExporterOption { Enabled = true, Endpoint = bad }, environment)
                .Match(
                    _ => output.WriteLine($"otlp accepted a {label}"),
                    error => output.WriteLine($"{label} rejected: {error.Code}"));
        }

        OtelHostExtensions
            .Duration(option.Metrics.Interval, "metrics interval")
            .Match(
                interval => output.WriteLine($"metrics interval: {interval}"),
                error => output.WriteLine($"interval rejected: {error}"));

        OtelHostExtensions
            .Duration("60s", "metrics interval")
            .Match(
                _ => output.WriteLine("duration accepted a bare-seconds value"),
                error => output.WriteLine($"bad duration rejected: {error.Message}"));
    }

    private static void Traces(TextWriter output)
    {
        output.WriteLine($"empty attribute map: {TraceAttributes.Empty.Count}");

        var attributes = new Dictionary<string, AttributeValue>(StringComparer.Ordinal)
        {
            ["route"] = AttributeValue.Text("/v1/demo"),
            ["attempt"] = AttributeValue.Integer(1),
            ["elapsed"] = AttributeValue.Duration(TimeSpan.FromMilliseconds(12)),
            ["retried"] = AttributeValue.Flag(false),
        };

        TraceAttributes
            .Check(attributes, "emit")
            .Match(
                sorted => output.WriteLine($"attributes checked: {string.Join(",", sorted.Keys)}"
                    + $" self-equal={TraceAttributes.Equal(sorted, sorted)}"),
                error => output.WriteLine($"attributes rejected: {error}"));

        TraceAttributes
            .Check(new Dictionary<string, AttributeValue> { [" "] = AttributeValue.Text("x") }, "emit")
            .Match(
                _ => output.WriteLine("attributes accepted a blank key"),
                error => output.WriteLine($"blank key rejected: {TraceWire.Name(error.Code)}"));

        var recorded = TraceEvent
            .Create("cache.miss", attributes)
            .Match(
                created => created,
                error => throw new InvalidOperationException(error.ToString()));
        output.WriteLine($"event: {recorded} attributes={recorded.Attributes.Count}"
            + $" self-equal={recorded.Equals(recorded)} hash={recorded.GetHashCode() != 0}");

        TraceEvent
            .Create(" ")
            .Match(
                _ => output.WriteLine("event accepted a blank name"),
                error => output.WriteLine($"blank event rejected: {error.Operation}"));

        var record = TraceRecord
            .Create("demo.request", attributes, [recorded], TraceStatus.Ok, "served")
            .Match(
                created => created,
                error => throw new InvalidOperationException(error.ToString()));
        output.WriteLine($"span: {record} events={record.Events.Count}"
            + $" status={TraceWire.Name(record.Status)}"
            + $" message={record.StatusMessage.GetOr("none")}"
            + $" self-equal={record.Equals(record)} hash={record.GetHashCode() != 0}");

        TraceRecord
            .Create("demo.request", statusMessage: " ")
            .Match(
                _ => output.WriteLine("span accepted a blank status message"),
                error => output.WriteLine($"blank status message rejected: {error.Code}"));

        Errors(output);
        Emit(output, record);
        Sinks(output, attributes);
    }

    private static void Errors(TextWriter output)
    {
        var invalid = TraceErrors.InvalidInput("emit", "bad span");
        var io = TraceErrors.Io("emit", "exporter refused");
        var unavailable = TraceErrors.Unavailable("emit", "shutting down");
        var unexpected = TraceErrors.UnexpectedCall("flush", "already disposed");

        var annotated = invalid.With("span", "demo.request");
        output.WriteLine($"errors: {invalid} | {io} | {unavailable} | {unexpected}");
        output.WriteLine($"annotated details: {string.Join(",", annotated.Details.Select(d => $"{d.Key}={d.Value}"))}"
            + $" equal={annotated == invalid} unequal={annotated != invalid}"
            + $" typed-equal={invalid.Equals((object)invalid)} hash={annotated.GetHashCode() != 0}");

        foreach (var wire in new[] { "unset", "ok", "error", "sideways" })
        {
            TraceWire
                .ParseStatus(wire)
                .Match(
                    status => output.WriteLine($"status '{wire}' -> {status}"),
                    error => output.WriteLine($"status '{wire}' rejected: {error.Message}"));
        }

        foreach (var wire in new[] { "invalid-input", "io", "unavailable", "unexpected-call", "nonsense" })
        {
            TraceWire
                .ParseErrorCode(wire)
                .Match(
                    code => output.WriteLine($"code '{wire}' -> {code}"),
                    error => output.WriteLine($"code '{wire}' rejected: {error.Message}"));
        }
    }

    private static void Emit(TextWriter output, TraceRecord record)
    {
        using var instrumentation = new Instrumentation(Identity);
        output.WriteLine($"instrumentation: activity-source={instrumentation.ActivitySource.Name}"
            + $" meter={instrumentation.Meter.Name} identity={instrumentation.Identity.Service}");

        var emitted = new List<string>();
        using var listener = new ActivityListener
        {
            ShouldListenTo = source => string.Equals(
                source.Name,
                instrumentation.ActivitySource.Name,
                StringComparison.Ordinal),
            Sample = (ref _) => ActivitySamplingResult.AllDataAndRecorded,
            ActivityStopped = activity => emitted.Add(
                $"{activity.DisplayName} status={activity.Status} tags={activity.TagObjects.Count()}"),
        };
        ActivitySource.AddActivityListener(listener);

        ITraceEmitter emitter = new ActivityTraceEmitter(instrumentation);
        emitter
            .Emit(record)
            .Match(
                _ => output.WriteLine($"activity emitted: {string.Join(";", emitted)}"),
                error => output.WriteLine($"activity emit failed: {error}"));
        emitter
            .Flush()
            .Match(
                _ => output.WriteLine("activity flushed"),
                error => output.WriteLine($"flush failed: {error}"));
    }

    private static void Sinks(TextWriter output, IReadOnlyDictionary<string, AttributeValue> attributes)
    {
        using var instrumentation = new Instrumentation(Identity);
        using var host = Builder(Sample(), OtelEnvironment.Process()).Build();

        var logger = host.Services.GetRequiredService<ILoggerSink>();
        var metrics = host.Services.GetRequiredService<IMetricsCollector>();
        var now = DateTimeOffset.UnixEpoch;

        foreach (var level in Enum.GetValues<LogLevel>())
        {
            output.WriteLine($"log level {level} -> {OtelLoggerSink.Level(level)}");
        }

        var failing = new LogRecord(now, LogLevel.Error, "demo failed", attributes, "boom", "at Demo.Run()");
        var state = OtelLoggerSink.State(failing);
        output.WriteLine($"log state carries {state.Count} entries including"
            + $" {OtelLoggerSink.ErrorKey} and {OtelLoggerSink.StackTraceKey}");

        logger
            .Emit(failing)
            .Match(
                _ => output.WriteLine("log emitted"),
                error => output.WriteLine($"log emit failed: {error.Id}"));

        foreach (var kind in Enum.GetValues<MetricKind>())
        {
            metrics
                .Emit(new MetricRecord(now, $"demo.{kind}".ToLowerInvariant(), kind, 1.5, "ms", attributes))
                .Match(
                    _ => output.WriteLine($"metric {kind} emitted"),
                    error => output.WriteLine($"metric {kind} failed: {error.Id}"));
        }

        var collector = new OtelMetricsCollector(instrumentation);
        collector
            .Emit(new MetricRecord(now, "demo.hostile", MetricKind.Gauge, double.NaN))
            .Match(
                _ => output.WriteLine("collector accepted NaN"),
                error => output.WriteLine($"NaN rejected: {error.Id}"));
    }

    private static HostApplicationBuilder Builder(
        OtelOption option,
        IReadOnlyDictionary<string, string?> environment)
    {
        var builder = Microsoft.Extensions.Hosting.Host.CreateApplicationBuilder();
        builder.AddAtomiOtel(Identity, option, environment);
        return builder;
    }

    private static int Host(
        TextWriter output,
        OtelOption option,
        IReadOnlyDictionary<string, string?> environment)
    {
        var wired = Microsoft.Extensions.Hosting.Host.CreateApplicationBuilder();
        var result = wired.AddAtomiOtel(Identity, option, environment);

        var bound = Microsoft.Extensions.Hosting.Host.CreateApplicationBuilder();
        bound.Configuration.AddInMemoryCollection(
        [
            new($"{OtelOption.Key}:Traces:Sampler:Type", OtelSampler.AlwaysOff),
            new($"{OtelOption.Key}:Logs:Exporter:Otlp:Enabled", "false"),
        ]);
        var boundResult = bound.AddAtomiOtel(Identity, bound.Configuration, environment);

        var disabled = Microsoft.Extensions.Hosting.Host.CreateApplicationBuilder();
        var disabledResult = disabled.AddAtomiOtel(
            Identity,
            option,
            new Dictionary<string, string?>(StringComparer.Ordinal)
            {
                [OtelEnvironment.SdkDisabledVariable] = "true",
            });

        // The bad-block probe deliberately ignores the caller's environment: an
        // OTEL_SDK_DISABLED in it would short-circuit wiring and make a broken block look
        // acceptable, which is the opposite of what this probe is for.
        var rejected = Microsoft.Extensions.Hosting.Host.CreateApplicationBuilder();
        var rejectedResult = rejected.AddAtomiOtel(
            Identity,
            new OtelOption { Metrics = new MetricsOption { Interval = "every minute" } },
            OtelEnvironment.Process());

        using var built = wired.Build();

        // Wiring can legitimately fail here — an OTEL_*_EXPORTER=otlp override selects an
        // exporter the sample block never gave an endpoint. Nothing is registered when
        // planning fails, so the seam is only resolvable on the success path.
        var emitter = result.Match(
            _ => built.Services.GetRequiredService<ITraceEmitter>().GetType().Name,
            error => $"not wired ({error.Code})");

        output.WriteLine($"host wired: {result.IsSuccess()}"
            + $" bound={boundResult.IsSuccess()}"
            + $" sdk-disabled={disabledResult.IsSuccess()}"
            + $" bad-interval-rejected={!rejectedResult.IsSuccess()}"
            + $" emitter={emitter}");

        return rejectedResult.Match(_ => 1, _ => 0);
    }
}
