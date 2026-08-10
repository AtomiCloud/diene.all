using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Config;

/// <summary>
/// Validated auth-engine configuration. The OIDC issuer is baked in at build time
/// and is never sourced from a discovery document, so a compromised document cannot
/// redirect trust to another issuer.
/// </summary>
public sealed class AuthEngineConfig
{
    private AuthEngineConfig(
        LogtoConfig logto,
        HandoffConfig handoff,
        TokenLifetimeConfig lifetimes,
        string homeLandscapeClaim)
    {
        this.Logto = logto;
        this.Handoff = handoff;
        this.Lifetimes = lifetimes;
        this.HomeLandscapeClaim = homeLandscapeClaim;
    }

    /// <summary>Gets the Logto identity-provider settings.</summary>
    public LogtoConfig Logto { get; }

    /// <summary>Gets the app-handoff controller-module settings.</summary>
    public HandoffConfig Handoff { get; }

    /// <summary>Gets the token lifetime settings.</summary>
    public TokenLifetimeConfig Lifetimes { get; }

    /// <summary>Gets the claim name carrying the user's home landscape.</summary>
    public string HomeLandscapeClaim { get; }

    /// <summary>
    /// Validates every field and returns a typed failure rather than throwing, so a
    /// misconfigured service fails fast at composition with an actionable reason.
    /// </summary>
    public static Result<AuthEngineConfig, ConfigError> Create(
        LogtoConfig? logto,
        HandoffConfig? handoff,
        TokenLifetimeConfig? lifetimes,
        string? homeLandscapeClaim)
    {
        if (logto is null) return new ConfigError("logto", "Logto configuration is required.");
        if (handoff is null) return new ConfigError("handoff", "Handoff configuration is required.");
        if (lifetimes is null) return new ConfigError("lifetimes", "Token lifetime configuration is required.");
        if (string.IsNullOrWhiteSpace(homeLandscapeClaim))
        {
            return new ConfigError("homeLandscapeClaim", "Home landscape claim name must not be blank.");
        }

        return new AuthEngineConfig(logto, handoff, lifetimes, homeLandscapeClaim.Trim());
    }
}
