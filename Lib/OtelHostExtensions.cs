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
        var instrumentation = new Instrumentation(identity);

        builder.Services.AddSingleton(identity);
        builder.Services.AddSingleton(instrumentation);
        builder.Services.AddSingleton<ITraceEmitter>(_ => new ActivityTraceEmitter(instrumentation));
        builder.Services.AddSingleton<IMetricsCollector>(_ => new OtelMetricsCollector(instrumentation));
        builder.Services.AddSingleton<ILoggerSink>(services => new OtelLoggerSink(
            services.GetRequiredService<ILoggerFactory>().CreateLogger(identity.Service)));

        if (OtelEnvironment.IsSdkDisabled(env)) return Result.Ok<Unit, TraceError>(default);

        return Signals(builder, identity, option, env, instrumentation);
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
    /// Applies the OTLP exporter settings. The programmatic endpoint is skipped when
    /// <c>OTEL_EXPORTER_OTLP_ENDPOINT</c> is set, so an ops redirect is never
    /// silently overwritten by the block it is meant to override.
    /// </summary>
    public static Result<Unit, TraceError> Otlp(
        OtlpExporterOptions target,
        OtlpExporterOption configured,
        IReadOnlyDictionary<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(target);
        ArgumentNullException.ThrowIfNull(configured);
        ArgumentNullException.ThrowIfNull(environment);

        target.Protocol = OtlpExportProtocol.HttpProtobuf;

        if (!OtelEnvironment.HasValue(environment, OtelEnvironment.OtlpEndpointVariable) &&
            !string.IsNullOrWhiteSpace(configured.Endpoint))
        {
            // A bare host:port parses as an absolute URI whose scheme is the hostname, so the
            // scheme has to be checked explicitly or 'collector:4318' silently becomes an endpoint.
            if (!Uri.TryCreate(configured.Endpoint.Trim(), UriKind.Absolute, out var endpoint) ||
                (endpoint.Scheme != Uri.UriSchemeHttp && endpoint.Scheme != Uri.UriSchemeHttps))
            {
                return TraceErrors.InvalidInput(
                    "exporter",
                    $"The OTLP endpoint must be an absolute http or https URI, but was '{configured.Endpoint}'.");
            }

            target.Endpoint = endpoint;
        }

        if (configured.Headers.Count > 0)
        {
            target.Headers = string.Join(',', configured.Headers.Select(header => $"{header.Key}={header.Value}"));
        }

        return Duration(configured.Timeout, "timeout")
            .Map(timeout =>
            {
                target.TimeoutMilliseconds = (int)timeout.TotalMilliseconds;
                return default(Unit);
            });
    }

    /// <summary>Parses an ISO 8601 duration from the block, reporting a bad value as a trace error.</summary>
    public static Result<TimeSpan, TraceError> Duration(string value, string field) =>
        Wire.ParseDuration(value)
            .MapFailure(error => TraceErrors.InvalidInput(
                "config",
                $"The otel {field} must be {error.Expected}, but was '{error.Actual}'."));

    private static Result<Unit, TraceError> Signals(
        IHostApplicationBuilder builder,
        AppIdentity identity,
        OtelOption option,
        IReadOnlyDictionary<string, string?> environment,
        Instrumentation instrumentation)
    {
        var resource = AtomiResource.Build(identity, environment);

        if (option.Logs.Enabled) Logs(builder, option.Logs, environment, resource);

        return Metrics(builder, option.Metrics, environment, instrumentation, resource)
            .Then(_ => Traces(builder, option.Traces, environment, instrumentation, resource));
    }

    private static void Logs(
        IHostApplicationBuilder builder,
        LogsOption option,
        IReadOnlyDictionary<string, string?> environment,
        OpenTelemetry.Resources.ResourceBuilder resource)
    {
        var selection = OtelEnvironment.Exporters(
            option.Exporter,
            OtelEnvironment.LogsExporterVariable,
            environment);

        builder.Logging.AddOpenTelemetry(logging =>
        {
            logging.IncludeScopes = true;
            logging.IncludeFormattedMessage = true;
            logging.SetResourceBuilder(resource);
            if (selection.Console) OpenTelemetry.Logs.ConsoleExporterLoggingExtensions.AddConsoleExporter(logging);
            if (selection.Otlp)
            {
                OpenTelemetry.Logs.OtlpLogExporterHelperExtensions.AddOtlpExporter(
                    logging,
                    target => Otlp(target, option.Exporter.Otlp, environment));
            }
        });
    }

    private static Result<Unit, TraceError> Metrics(
        IHostApplicationBuilder builder,
        MetricsOption option,
        IReadOnlyDictionary<string, string?> environment,
        Instrumentation instrumentation,
        OpenTelemetry.Resources.ResourceBuilder resource)
    {
        if (!option.Enabled) return Result.Ok<Unit, TraceError>(default);

        return Duration(option.Interval, "metrics interval").Map(interval =>
        {
            var selection = OtelEnvironment.Exporters(
                option.Exporter,
                OtelEnvironment.MetricsExporterVariable,
                environment);

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
                            reader.PeriodicExportingMetricReaderOptions.ExportIntervalMilliseconds =
                                (int)interval.TotalMilliseconds);
                    }

                    if (selection.Otlp)
                    {
                        metrics.AddOtlpExporter((target, reader) =>
                        {
                            Otlp(target, option.Exporter.Otlp, environment);
                            reader.PeriodicExportingMetricReaderOptions.ExportIntervalMilliseconds =
                                (int)interval.TotalMilliseconds;
                        });
                    }
                });

            return default(Unit);
        });
    }

    private static Result<Unit, TraceError> Traces(
        IHostApplicationBuilder builder,
        TracesOption option,
        IReadOnlyDictionary<string, string?> environment,
        Instrumentation instrumentation,
        OpenTelemetry.Resources.ResourceBuilder resource)
    {
        if (!option.Enabled) return Result.Ok<Unit, TraceError>(default);

        return OtelSampler.Create(option.Sampler, environment).Map(sampler =>
        {
            var selection = OtelEnvironment.Exporters(
                option.Exporter,
                OtelEnvironment.TracesExporterVariable,
                environment);

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
                    if (selection.Otlp)
                    {
                        tracing.AddOtlpExporter(target => Otlp(target, option.Exporter.Otlp, environment));
                    }
                });

            return default(Unit);
        });
    }
}
