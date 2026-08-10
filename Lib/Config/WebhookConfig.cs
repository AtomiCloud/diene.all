using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ServerEngine.Config;

/// <summary>
/// Settings for the internal webhook receiver. Only the timestamp tolerance is
/// configurable, and only downward.
/// </summary>
/// <remarks>
/// C0 §11 fixes the route, the header name, the media type, and the ±5 minute window, so
/// none of those are options. The tolerance is exposed because a receiver may legitimately
/// want a TIGHTER window than the contract's maximum; it is clamped so a configuration
/// mistake cannot widen the replay window the contract bounds.
/// </remarks>
public sealed class WebhookConfig
{
    /// <summary>The contract's maximum accepted clock difference between mercury and this receiver.</summary>
    public static readonly TimeSpan MaximumTolerance = TimeSpan.FromMinutes(5);

    private WebhookConfig(TimeSpan tolerance) => this.Tolerance = tolerance;

    /// <summary>Gets the accepted absolute difference between the signed timestamp and now.</summary>
    public TimeSpan Tolerance { get; }

    /// <summary>Gets the settings using the contract's full ±5 minute window.</summary>
    public static WebhookConfig Default { get; } = new(MaximumTolerance);

    /// <summary>
    /// Validates a consumer-supplied tolerance. Rejects a non-positive window and any
    /// value above the contract maximum rather than silently clamping, because a receiver
    /// that asked for ten minutes and got five should be told so at composition.
    /// </summary>
    public static Result<WebhookConfig, ServerEngineConfigError> Create(TimeSpan tolerance)
    {
        if (tolerance <= TimeSpan.Zero)
        {
            return new ServerEngineConfigError("webhooks.tolerance", "Tolerance must be positive.");
        }

        return tolerance > MaximumTolerance
            ? new ServerEngineConfigError(
                "webhooks.tolerance",
                $"Tolerance must not exceed the C0 maximum of {MaximumTolerance.TotalSeconds:F0} seconds.")
            : new WebhookConfig(tolerance);
    }
}
