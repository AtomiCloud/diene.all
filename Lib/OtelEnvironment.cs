namespace AtomiCloud.Diene.Otel;

/// <summary>Which exporters a signal actually writes to, after env overrides.</summary>
/// <param name="Console">Whether the stdout exporter is selected.</param>
/// <param name="Otlp">Whether the OTLP exporter is selected.</param>
public readonly record struct ExporterSelection(bool Console, bool Otlp);

/// <summary>
/// The C0 §4 escape hatch: standard <c>OTEL_*</c> environment variables win over
/// the config block, so ops can redirect or silence telemetry without a redeploy.
/// The environment is injected rather than read from the process, so precedence is
/// testable without mutating global state.
/// </summary>
public static class OtelEnvironment
{
    /// <summary>The env var that selects log exporters.</summary>
    public const string LogsExporterVariable = "OTEL_LOGS_EXPORTER";

    /// <summary>The env var that selects metric exporters.</summary>
    public const string MetricsExporterVariable = "OTEL_METRICS_EXPORTER";

    /// <summary>The env var that selects trace exporters.</summary>
    public const string TracesExporterVariable = "OTEL_TRACES_EXPORTER";

    /// <summary>The env var that overrides the OTLP endpoint for every signal.</summary>
    public const string OtlpEndpointVariable = "OTEL_EXPORTER_OTLP_ENDPOINT";

    /// <summary>The env var that supplies extra resource attributes.</summary>
    public const string ResourceAttributesVariable = "OTEL_RESOURCE_ATTRIBUTES";

    /// <summary>The env var that overrides <c>service.name</c>.</summary>
    public const string ServiceNameVariable = "OTEL_SERVICE_NAME";

    /// <summary>The env var that overrides the sampler.</summary>
    public const string TracesSamplerVariable = "OTEL_TRACES_SAMPLER";

    /// <summary>The env var that disables the whole SDK.</summary>
    public const string SdkDisabledVariable = "OTEL_SDK_DISABLED";

    /// <summary>Reads the process environment as an injectable map.</summary>
    public static IReadOnlyDictionary<string, string?> Process()
    {
        var environment = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (var entry in Environment.GetEnvironmentVariables().Cast<System.Collections.DictionaryEntry>())
        {
            environment[(string)entry.Key] = entry.Value as string;
        }

        return environment;
    }

    /// <summary>Whether the variable carries a usable, non-blank value.</summary>
    public static bool HasValue(IReadOnlyDictionary<string, string?> environment, string name)
    {
        ArgumentNullException.ThrowIfNull(environment);
        return environment.TryGetValue(name, out var value) && !string.IsNullOrWhiteSpace(value);
    }

    /// <summary>
    /// Whether <c>OTEL_SDK_DISABLED=true</c> is set. This wins over every
    /// <c>otel.&lt;signal&gt;.enabled=true</c> in the block (C0 §4).
    /// </summary>
    public static bool IsSdkDisabled(IReadOnlyDictionary<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(environment);
        return environment.TryGetValue(SdkDisabledVariable, out var value) &&
               string.Equals(value?.Trim(), "true", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Resolves the exporters for one signal. An unset or blank override defers to
    /// the block; <c>none</c> silences the signal; otherwise the override is a
    /// comma-separated set membership test, so an override that names neither
    /// exporter turns both off.
    /// </summary>
    public static ExporterSelection Exporters(
        ExporterOption configured,
        string variable,
        IReadOnlyDictionary<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(configured);
        ArgumentNullException.ThrowIfNull(environment);

        if (!HasValue(environment, variable))
        {
            return new ExporterSelection(configured.Console.Enabled, configured.Otlp.Enabled);
        }

        var selected = environment[variable]!
            .Split(',')
            .Select(value => value.Trim().ToLowerInvariant())
            .ToHashSet(StringComparer.Ordinal);

        return selected.Contains("none")
            ? new ExporterSelection(false, false)
            : new ExporterSelection(selected.Contains("console"), selected.Contains("otlp"));
    }
}
