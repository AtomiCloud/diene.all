using AtomiCloud.Diene.CoreUtils;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Exporter;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;

namespace AtomiCloud.Diene.Otel;

/// <summary>
/// Wires the three OpenTelemetry signals onto a host from the canonical
/// <c>otel:</c> block. Everything is OFF unless the block turns it on, and the
/// standard <c>OTEL_*</c> variables win over the block, so a landscape overlay and
/// an ops override reach the same pipeline through one code path.
/// </summary>
public static class OtelHostExtensions
{
    /// <summary>The OTLP path every signal appends to a base endpoint.</summary>
    public const string OtlpProtocol = "http/protobuf";

    /// <summary>
    /// Registers the identity, instrumentation, and seam implementations, then builds
    /// whichever signal pipelines the resolved configuration asks for. A rejected
    /// duration or sampler is returned as a value: a service must fail its own
    /// startup deliberately, not through an exception thrown out of a wiring call.
    /// </summary>
    /// <param name="builder">The host being configured.</param>
    /// <param name="identity">The service identity that names the resource.</param>
    /// <param name="option">The canonical <c>otel:</c> block.</param>
    /// <param name="environment">The environment to resolve overrides from.</param>
    public static Result<Unit, TraceError> AddAtomiOtel(
        this IHostApplicationBuilder builder,
        AppIdentity identity,
        OtelOption option,
        IReadOnlyDictionary<string, string?>? environment = null)
    {
        ArgumentNullException.ThrowIfNull(builder);
        ArgumentNullException.ThrowIfNull(identity);
        ArgumentNullException.ThrowIfNull(option);

        var env = environment ?? OtelEnvironment.Process();

        // Plan first, register second. Every signal is validated against the whole block
        // before the builder is touched at all, so a bad traces endpoint cannot leave a
        // half-wired logs pipeline behind on a host whose startup then fails.
        var disabled = OtelEnvironment.IsSdkDisabled(env);
        var planned = disabled
            ? Result.Ok<Option<OtelPlan>, TraceError>(Option.None<OtelPlan>())
            : Plan(option, env).Map(Option.Some);

        return planned.Map(plan =>
        {
            var instrumentation = new Instrumentation(identity);

            builder.Services.AddSingleton(identity);
            builder.Services.AddSingleton(instrumentation);
            builder.Services.AddSingleton<ITraceEmitter>(_ => new ActivityTraceEmitter(instrumentation));
            builder.Services.AddSingleton<IMetricsCollector>(_ => new OtelMetricsCollector(instrumentation));
            builder.Services.AddSingleton<ILoggerSink>(services => new OtelLoggerSink(
                services.GetRequiredService<ILoggerFactory>().CreateLogger(identity.Service)));

            // OTEL_SDK_DISABLED keeps the seams available and builds no pipeline at all.
            if (plan.IsSome(out var pipelines)) Register(builder, identity, env, instrumentation, pipelines);

            return default(Unit);
        });
    }

    /// <summary>
    /// Binds the <c>otel:</c> block out of configuration and wires it. This is the
    /// overload a host uses: the block reaches the engine through the same
    /// <c>IConfiguration</c> layering that merges every other block.
    /// </summary>
    /// <param name="builder">The host being configured.</param>
    /// <param name="identity">The service identity that names the resource.</param>
    /// <param name="configuration">The configuration root holding the <c>Otel</c> section.</param>
    /// <param name="environment">The environment to resolve overrides from.</param>
    public static Result<Unit, TraceError> AddAtomiOtel(
        this IHostApplicationBuilder builder,
        AppIdentity identity,
        IConfiguration configuration,
        IReadOnlyDictionary<string, string?>? environment = null)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        var option = configuration.GetSection(OtelOption.Key).Get<OtelOption>() ?? new OtelOption();
        return builder.AddAtomiOtel(identity, option, environment);
    }

    /// <summary>
    /// The settings an OTLP exporter will be configured with. Only
    /// <see cref="Preflight" /> can construct one, so a value of this type is proof
    /// that the endpoint, protocol, and timeout were validated — a caller cannot
    /// hand <see cref="Apply" /> a negative timeout or an unchecked endpoint.
    /// </summary>
    public sealed class OtlpSettings
    {
        internal OtlpSettings(Option<Uri> endpoint, Option<string> headers, int timeoutMilliseconds)
        {
            Endpoint = endpoint;
            Headers = headers;
            TimeoutMilliseconds = timeoutMilliseconds;
        }

        /// <summary>The endpoint to set, absent when the environment override owns it.</summary>
        public Option<Uri> Endpoint { get; }

        /// <summary>The header string, absent when the block carries none.</summary>
        public Option<string> Headers { get; }

        /// <summary>
        /// The export timeout, already reduced to the whole milliseconds the SDK takes.
        /// Validated to be positive and in range, so applying it cannot overflow.
        /// </summary>
        public int TimeoutMilliseconds { get; }
    }

    /// <summary>
    /// Reduces a duration to the whole milliseconds every OpenTelemetry knob is
    /// expressed in. A syntactically valid ISO duration can still be zero, negative,
    /// or larger than <see cref="int.MaxValue" /> milliseconds, and casting those
    /// straight to <c>int</c> yields a silently unusable or overflowed setting — so
    /// the range is a validation step, not a cast.
    /// </summary>
    public static Result<int, TraceError> Milliseconds(string? value, string field) =>
        Duration(value, field).Then(duration =>
            duration.TotalMilliseconds is >= 1 and <= int.MaxValue
                ? Result.Ok<int, TraceError>((int)duration.TotalMilliseconds)
                : TraceErrors.InvalidInput(
                    "config",
                    $"The otel {field} must be between 1ms and {int.MaxValue}ms, but was '{value}'."));

    /// <summary>
    /// Validates one OTLP exporter block. The endpoint must be a non-blank absolute
    /// HTTP(S) URI on the fleet's explicit port 4318 (C0 §4, R14) — unless
    /// <c>OTEL_EXPORTER_OTLP_ENDPOINT</c> is set, in which case the SDK reads the
    /// endpoint from the environment and any block endpoint is ignored.
    /// </summary>
    public static Result<OtlpSettings, TraceError> Preflight(
        OtlpExporterOption configured,
        IReadOnlyDictionary<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(configured);
        ArgumentNullException.ThrowIfNull(environment);

        if (!string.Equals(configured.Protocol, OtlpProtocol, StringComparison.Ordinal))
        {
            return TraceErrors.InvalidInput(
                "exporter",
                $"The OTLP protocol is pinned to '{OtlpProtocol}' fleet-wide, but was '{configured.Protocol}'.");
        }

        // Every field below is bound from external configuration, so a null is an
        // ordinary bad-input case rather than a programming error: it comes back as a
        // rejection, never as a NullReferenceException out of a wiring call.
        var headers = configured.Headers is null or { Count: 0 }
            ? Option.None<string>()
            : Option.Some(string.Join(',', configured.Headers.Select(header => $"{header.Key}={header.Value}")));

        return Endpoint(configured, environment)
            .Then(endpoint => Milliseconds(configured.Timeout, "timeout")
                .Map(timeout => new OtlpSettings(endpoint, headers, timeout)));
    }

    /// <summary>Applies already-validated settings to a live exporter.</summary>
    public static void Apply(OtlpExporterOptions target, OtlpSettings settings)
    {
        ArgumentNullException.ThrowIfNull(target);
        ArgumentNullException.ThrowIfNull(settings);
        target.Protocol = OtlpExportProtocol.HttpProtobuf;
        if (settings.Endpoint.IsSome(out var endpoint)) target.Endpoint = endpoint;
        if (settings.Headers.IsSome(out var headers)) target.Headers = headers;
        target.TimeoutMilliseconds = settings.TimeoutMilliseconds;
    }

    /// <summary>The fleet's OTLP HTTP port. Traffic on any other port is refused (C0 §4).</summary>
    public const int OtlpPort = 4318;

    private static Result<Option<Uri>, TraceError> Endpoint(
        OtlpExporterOption configured,
        IReadOnlyDictionary<string, string?> environment)
    {
        // An ops override owns the endpoint entirely; the block must not fight it.
        if (OtelEnvironment.HasValue(environment, OtelEnvironment.OtlpEndpointVariable))
        {
            return Result.Ok<Option<Uri>, TraceError>(Option.None<Uri>());
        }

        if (string.IsNullOrWhiteSpace(configured.Endpoint))
        {
            return TraceErrors.InvalidInput(
                "exporter",
                "An enabled OTLP exporter needs an endpoint: set it in the block or "
                + $"set {OtelEnvironment.OtlpEndpointVariable}.");
        }

        // A bare host:port parses as an absolute URI whose scheme is the hostname, so the
        // scheme has to be checked explicitly or 'collector:4318' silently becomes an endpoint.
        if (!Uri.TryCreate(configured.Endpoint.Trim(), UriKind.Absolute, out var endpoint) ||
            (endpoint.Scheme != Uri.UriSchemeHttp && endpoint.Scheme != Uri.UriSchemeHttps))
        {
            return TraceErrors.InvalidInput(
                "exporter",
                $"The OTLP endpoint must be an absolute http or https URI, but was '{configured.Endpoint}'.");
        }

        // IsDefaultPort means the URI carried no explicit port. The fleet pins 4318, so an
        // implicit 80/443 and zinc's 4317 are both refused rather than silently accepted.
        if (endpoint.IsDefaultPort || endpoint.Port != OtlpPort)
        {
            return TraceErrors.InvalidInput(
                "exporter",
                $"The OTLP endpoint must name the fleet port :{OtlpPort} explicitly, "
                + $"but was '{configured.Endpoint}'.");
        }

        return Result.Ok<Option<Uri>, TraceError>(Option.Some(endpoint));
    }

    /// <summary>
    /// Parses an ISO 8601 duration from the block, reporting a bad value as a trace
    /// error. The value is bound from external configuration, so an absent one is a
    /// rejection rather than the exception the underlying parser would throw.
    /// </summary>
    public static Result<TimeSpan, TraceError> Duration(string? value, string field) =>
        value is null
            ? TraceErrors.InvalidInput("config", $"The otel {field} must be an ISO 8601 duration, but was absent.")
            : Wire.ParseDuration(value)
                .MapFailure(error => TraceErrors.InvalidInput(
                    "config",
                    $"The otel {field} must be {error.Expected}, but was '{error.Actual}'."));

    /// <summary>
    /// One signal's validated wiring: whether it is built at all, which exporters it
    /// writes to, and the OTLP settings when that exporter is selected.
    /// </summary>
    private readonly record struct SignalPlan(
        bool Enabled,
        ExporterSelection Selection,
        Option<OtlpSettings> Otlp);

    /// <summary>
    /// The whole block, validated. Producing one of these mutates nothing, so a
    /// failure anywhere leaves the host exactly as it was.
    /// </summary>
    private readonly record struct OtelPlan(
        SignalPlan Logs,
        SignalPlan Metrics,
        int IntervalMilliseconds,
        SignalPlan Traces,
        Option<Sampler> Sampler);

    /// <summary>
    /// Validates every enabled signal against the block and the environment,
    /// returning the FIRST error. Nothing here touches the builder.
    /// </summary>
    private static Result<OtelPlan, TraceError> Plan(
        OtelOption option,
        IReadOnlyDictionary<string, string?> environment) =>
        Signal(option.Logs, option.Logs.Exporter, OtelEnvironment.LogsExporterVariable, environment)
            .Then(logs => Signal(
                    option.Metrics,
                    option.Metrics.Exporter,
                    OtelEnvironment.MetricsExporterVariable,
                    environment)
                .Then(metrics => Interval(option.Metrics)
                    .Then(interval => Signal(
                            option.Traces,
                            option.Traces.Exporter,
                            OtelEnvironment.TracesExporterVariable,
                            environment)
                        .Then(traces => Sampler(option.Traces, environment)
                            .Map(sampler => new OtelPlan(logs, metrics, interval, traces, sampler))))));

    /// <summary>
    /// Validates one signal. A disabled signal, or one whose OTLP exporter is not
    /// selected, has nothing to validate — an unusable OTLP block that nobody
    /// selected must not fail a host that was never going to export through it.
    /// </summary>
    private static Result<SignalPlan, TraceError> Signal(
        SignalOption option,
        ExporterOption exporter,
        string variable,
        IReadOnlyDictionary<string, string?> environment)
    {
        if (!option.Enabled) return Result.Ok<SignalPlan, TraceError>(default);

        var selection = OtelEnvironment.Exporters(exporter, variable, environment);
        return selection.Otlp
            ? Preflight(exporter.Otlp, environment)
                .Map(settings => new SignalPlan(true, selection, Option.Some(settings)))
            : Result.Ok<SignalPlan, TraceError>(new SignalPlan(true, selection, Option.None<OtlpSettings>()));
    }

    private static Result<int, TraceError> Interval(MetricsOption option) =>
        option.Enabled
            ? Milliseconds(option.Interval, "metrics interval")
            : Result.Ok<int, TraceError>(0);

    private static Result<Option<Sampler>, TraceError> Sampler(
        TracesOption option,
        IReadOnlyDictionary<string, string?> environment) =>
        option.Enabled
            ? OtelSampler.Create(option.Sampler, environment)
            : Result.Ok<Option<Sampler>, TraceError>(Option.None<Sampler>());

    /// <summary>Builds every pipeline from an already-validated plan.</summary>
    private static void Register(
        IHostApplicationBuilder builder,
        AppIdentity identity,
        IReadOnlyDictionary<string, string?> environment,
        Instrumentation instrumentation,
        OtelPlan plan)
    {
        var resource = AtomiResource.Build(identity, environment);

        if (plan.Logs.Enabled) LogPipeline(builder, plan.Logs.Selection, plan.Logs.Otlp, resource);
        if (plan.Metrics.Enabled) MetricPipeline(builder, plan, instrumentation, resource);
        if (plan.Traces.Enabled) TracePipeline(builder, plan, instrumentation, resource);
    }

    private static void LogPipeline(
        IHostApplicationBuilder builder,
        ExporterSelection selection,
        Option<OtlpSettings> otlp,
        OpenTelemetry.Resources.ResourceBuilder resource)
    {
        builder.Logging.AddOpenTelemetry(logging =>
        {
            logging.IncludeScopes = true;
            logging.IncludeFormattedMessage = true;
            logging.SetResourceBuilder(resource);
            if (selection.Console) OpenTelemetry.Logs.ConsoleExporterLoggingExtensions.AddConsoleExporter(logging);
            if (otlp.IsSome(out var settings))
            {
                OpenTelemetry.Logs.OtlpLogExporterHelperExtensions.AddOtlpExporter(
                    logging,
                    target => Apply(target, settings));
            }
        });
    }

    private static void MetricPipeline(
        IHostApplicationBuilder builder,
        OtelPlan plan,
        Instrumentation instrumentation,
        OpenTelemetry.Resources.ResourceBuilder resource)
    {
        var selection = plan.Metrics.Selection;
        var otlp = plan.Metrics.Otlp;
        var interval = plan.IntervalMilliseconds;

        builder.Services
                .AddOpenTelemetry()
                .WithMetrics(metrics =>
                {
                    metrics
                        .SetResourceBuilder(resource)
                        .AddMeter(instrumentation.Meter.Name)
                        .AddAspNetCoreInstrumentation()
                        .AddHttpClientInstrumentation()
                        .AddRuntimeInstrumentation();

                    if (selection.Console)
                    {
                        metrics.AddConsoleExporter((_, reader) =>
                            reader.PeriodicExportingMetricReaderOptions.ExportIntervalMilliseconds = interval);
                    }

                    if (otlp.IsSome(out var settings))
                    {
                        metrics.AddOtlpExporter((target, reader) =>
                        {
                            Apply(target, settings);
                            reader.PeriodicExportingMetricReaderOptions.ExportIntervalMilliseconds = interval;
                        });
                    }
                });
    }

    private static void TracePipeline(
        IHostApplicationBuilder builder,
        OtelPlan plan,
        Instrumentation instrumentation,
        OpenTelemetry.Resources.ResourceBuilder resource)
    {
        var selection = plan.Traces.Selection;
        var otlp = plan.Traces.Otlp;
        var sampler = plan.Sampler;

        builder.Services
                .AddOpenTelemetry()
                .WithTracing(tracing =>
                {
                    tracing
                        .SetResourceBuilder(resource)
                        .AddSource(instrumentation.ActivitySource.Name)
                        .AddAspNetCoreInstrumentation()
                        .AddHttpClientInstrumentation();

                    if (sampler.IsSome(out var selected)) tracing.SetSampler(selected);
                    if (selection.Console) tracing.AddConsoleExporter();
                    if (otlp.IsSome(out var settings)) tracing.AddOtlpExporter(target => Apply(target, settings));
                });
    }
}
