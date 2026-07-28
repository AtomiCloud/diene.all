using AtomiCloud.Diene.CoreUtils;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ApiEngine.Config;

/// <summary>
/// One validated upstream: a single base address, a resolved timeout, and the optional
/// per-backend auth binding.
/// </summary>
public sealed class UpstreamConfig
{
    private UpstreamConfig(
        Uri baseAddress,
        TimeSpan timeout,
        string? authResource,
        IReadOnlyList<string> authScopes,
        bool rescueRoutingEnabled)
    {
        BaseAddress = baseAddress;
        Timeout = timeout;
        AuthResource = authResource;
        AuthScopes = authScopes;
        RescueRoutingEnabled = rescueRoutingEnabled;
    }

    /// <summary>Gets the single base address requests are sent to.</summary>
    public Uri BaseAddress { get; }

    /// <summary>Gets the resolved request timeout.</summary>
    public TimeSpan Timeout { get; }

    /// <summary>Gets the auth-engine resource, or null when this upstream is unauthenticated.</summary>
    public string? AuthResource { get; }

    /// <summary>Gets the scopes requested for <see cref="AuthResource" />.</summary>
    public IReadOnlyList<string> AuthScopes { get; }

    /// <summary>Gets whether a hard connect failure against this upstream is rescuable.</summary>
    public bool RescueRoutingEnabled { get; }

    /// <summary>
    /// Validates one configuration entry. The timeout is read through the C0 duration
    /// codec rather than a bespoke parse, so an ISO 8601 duration means the same thing here
    /// as it does anywhere else in the platform.
    /// </summary>
    public static Result<UpstreamConfig, ApiConfigError> Create(string field, HttpClientOption? option)
    {
        if (option is null)
        {
            return new ApiConfigError(field, "Upstream configuration is required.");
        }

        if (string.IsNullOrWhiteSpace(option.BaseAddress))
        {
            return new ApiConfigError($"{field}.baseAddress", "Base address must not be blank.");
        }

        if (!Uri.TryCreate(option.BaseAddress.Trim(), UriKind.Absolute, out var baseAddress) ||
            (baseAddress.Scheme != Uri.UriSchemeHttp && baseAddress.Scheme != Uri.UriSchemeHttps))
        {
            return new ApiConfigError($"{field}.baseAddress", "Base address must be an absolute http or https URI.");
        }

        if (!string.IsNullOrEmpty(baseAddress.Query) || !string.IsNullOrEmpty(baseAddress.Fragment))
        {
            return new ApiConfigError($"{field}.baseAddress", "Base address must not carry a query or fragment.");
        }

        var duration = Wire.ParseDuration(option.Timeout ?? string.Empty);
        if (duration.IsFailure(out var durationError))
        {
            return new ApiConfigError(
                $"{field}.timeout",
                $"Timeout must be an ISO 8601 duration; expected {durationError.Expected} but found '{durationError.Actual}'.");
        }

        var timeout = duration.Get();
        if (timeout <= TimeSpan.Zero)
        {
            return new ApiConfigError($"{field}.timeout", "Timeout must be greater than zero.");
        }

        var resource = string.IsNullOrWhiteSpace(option.AuthResource) ? null : option.AuthResource.Trim();
        var scopes = option.AuthScopes
            .Where(scope => !string.IsNullOrWhiteSpace(scope))
            .Select(scope => scope.Trim())
            .ToArray();

        if (resource is null && scopes.Length > 0)
        {
            return new ApiConfigError(
                $"{field}.authScopes",
                "Scopes were requested without an auth resource; an unauthenticated upstream cannot carry scopes.");
        }

        return new UpstreamConfig(baseAddress, timeout, resource, scopes, option.RescueRoutingEnabled);
    }
}
