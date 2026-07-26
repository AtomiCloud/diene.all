namespace AtomiCloud.Diene.Otel;

/// <summary>
/// The canonical <c>otel:</c> configuration block (C0 §4). .NET is the priority
/// language for this shape, so these Options classes ARE the reference binding:
/// per-signal <c>logs</c>/<c>metrics</c>/<c>traces</c> keys, per-exporter
/// <c>enabled</c> bools (no enum strings), and ISO 8601 duration strings on the
/// wire.
/// </summary>
public sealed class OtelOption
{
    /// <summary>The configuration section this block binds to.</summary>
    public const string Key = "Otel";

    /// <summary>The structured-logging signal.</summary>
    public LogsOption Logs { get; set; } = new();

    /// <summary>The metrics signal.</summary>
    public MetricsOption Metrics { get; set; } = new();

    /// <summary>The tracing signal.</summary>
    public TracesOption Traces { get; set; } = new();
}

/// <summary>The shape shared by every signal: an on/off flag and its exporters.</summary>
public class SignalOption
{
    /// <summary>Whether the signal pipeline is built at all.</summary>
    [Required]
    public bool Enabled { get; set; } = true;

    /// <summary>The exporters this signal writes to.</summary>
    public ExporterOption Exporter { get; set; } = new();
}

/// <summary>The <c>otel:logs</c> signal.</summary>
public sealed class LogsOption : SignalOption;

/// <summary>The <c>otel:metrics</c> signal.</summary>
public sealed class MetricsOption : SignalOption
{
    /// <summary>The reader export interval, as an ISO 8601 duration (C0 §1).</summary>
    [Required]
    public string Interval { get; set; } = "PT60S";
}

/// <summary>The <c>otel:traces</c> signal.</summary>
public sealed class TracesOption : SignalOption
{
    /// <summary>How sampling decisions are made.</summary>
    public SamplerOption Sampler { get; set; } = new();
}

/// <summary>The trace sampler selection.</summary>
public sealed class SamplerOption
{
    /// <summary>The sampler name.</summary>
    [Required]
    [AllowedValues("parentbased_traceidratio", "always_on", "always_off")]
    public string Type { get; set; } = "parentbased_traceidratio";

    /// <summary>The ratio a ratio-based sampler keeps.</summary>
    [Range(0.0, 1.0)]
    public double Ratio { get; set; } = 1.0;
}

/// <summary>The exporters available to every signal.</summary>
public sealed class ExporterOption
{
    /// <summary>The stdout exporter, for local development.</summary>
    public ConsoleExporterOption Console { get; set; } = new();

    /// <summary>The OTLP exporter, for real collectors.</summary>
    public OtlpExporterOption Otlp { get; set; } = new();
}

/// <summary>The stdout exporter.</summary>
public sealed class ConsoleExporterOption
{
    /// <summary>Off by default everywhere (C0 §4); the lapras overlay flips it on.</summary>
    [Required]
    public bool Enabled { get; set; }
}

/// <summary>The OTLP exporter, pinned to <c>http/protobuf</c> fleet-wide (R17).</summary>
public sealed class OtlpExporterOption
{
    /// <summary>Off by default; a landscape overlay flips it on.</summary>
    [Required]
    public bool Enabled { get; set; }

    /// <summary>The collector endpoint, e.g. <c>http://collector:4318</c>.</summary>
    public string Endpoint { get; set; } = "";

    /// <summary>The wire protocol, fixed fleet-wide (R17) — zinc's gRPC/4317 drift dies here.</summary>
    [Required]
    [AllowedValues("http/protobuf")]
    public string Protocol { get; set; } = "http/protobuf";

    /// <summary>Headers sent with every export request.</summary>
    public Dictionary<string, string> Headers { get; set; } = [];

    /// <summary>The export timeout, as an ISO 8601 duration (C0 §1).</summary>
    [Required]
    public string Timeout { get; set; } = "PT10S";
}
