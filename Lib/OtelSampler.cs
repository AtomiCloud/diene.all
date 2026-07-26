using OpenTelemetry.Trace;

namespace AtomiCloud.Diene.Otel;

/// <summary>
/// Maps the block's sampler selection onto an OpenTelemetry sampler.
/// <c>OTEL_TRACES_SAMPLER</c> suppresses the programmatic sampler entirely so the
/// SDK's own environment handling wins, matching the bun sibling.
/// </summary>
public static class OtelSampler
{
    /// <summary>The ratio-based sampler wrapped in a parent-based decision.</summary>
    public const string ParentBasedTraceIdRatio = "parentbased_traceidratio";

    /// <summary>The sampler that keeps every span.</summary>
    public const string AlwaysOn = "always_on";

    /// <summary>The sampler that drops every span.</summary>
    public const string AlwaysOff = "always_off";

    /// <summary>
    /// Resolves the sampler for a trace pipeline. The absent case means "leave the
    /// SDK's default alone", which is what an <c>OTEL_TRACES_SAMPLER</c> override
    /// needs, and an unrecognized type is a value-level failure rather than a throw.
    /// </summary>
    public static Result<Option<Sampler>, TraceError> Create(
        SamplerOption configured,
        IReadOnlyDictionary<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(configured);
        ArgumentNullException.ThrowIfNull(environment);

        if (OtelEnvironment.HasValue(environment, OtelEnvironment.TracesSamplerVariable))
        {
            return Result.Ok<Option<Sampler>, TraceError>(Option.None<Sampler>());
        }

        return configured.Type switch
        {
            AlwaysOn => Selected(new AlwaysOnSampler()),
            AlwaysOff => Selected(new AlwaysOffSampler()),
            ParentBasedTraceIdRatio when configured.Ratio is >= 0.0 and <= 1.0 =>
                Selected(new ParentBasedSampler(new TraceIdRatioBasedSampler(configured.Ratio))),
            ParentBasedTraceIdRatio => TraceErrors.InvalidInput(
                "sampler",
                $"The sampler ratio must be between 0 and 1, but was {configured.Ratio}."),
            _ => TraceErrors.InvalidInput("sampler", $"'{configured.Type}' is not a supported sampler type."),
        };
    }

    private static Result<Option<Sampler>, TraceError> Selected(Sampler sampler) =>
        Result.Ok<Option<Sampler>, TraceError>(Option.Some(sampler));
}
