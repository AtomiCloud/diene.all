using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Config;

/// <summary>
/// Token lifetime settings. The defaults are the alcohol-parity values: 10-minute
/// access tokens and 14-day rotating refresh tokens, with apps re-minting on open
/// so a fresh session always starts with a fresh access token.
/// </summary>
public sealed class TokenLifetimeConfig
{
    /// <summary>Alcohol-parity access-token lifetime.</summary>
    public static readonly TimeSpan DefaultAccessLifetime = TimeSpan.FromMinutes(10);

    /// <summary>Alcohol-parity refresh-token lifetime.</summary>
    public static readonly TimeSpan DefaultRefreshLifetime = TimeSpan.FromDays(14);

    /// <summary>Clock skew tolerated when deciding whether a token has expired.</summary>
    public static readonly TimeSpan DefaultExpirySkew = TimeSpan.FromSeconds(30);

    private TokenLifetimeConfig(TimeSpan access, TimeSpan refresh, TimeSpan skew, bool rotateRefreshTokens)
    {
        this.Access = access;
        this.Refresh = refresh;
        this.ExpirySkew = skew;
        this.RotateRefreshTokens = rotateRefreshTokens;
    }

    /// <summary>Gets the access-token lifetime.</summary>
    public TimeSpan Access { get; }

    /// <summary>Gets the refresh-token lifetime.</summary>
    public TimeSpan Refresh { get; }

    /// <summary>Gets the skew applied to expiry decisions.</summary>
    public TimeSpan ExpirySkew { get; }

    /// <summary>
    /// Gets whether each refresh issues a new refresh token. Rotation is what makes
    /// reuse detection able to catch a stolen token, so it defaults to on.
    /// </summary>
    public bool RotateRefreshTokens { get; }

    /// <summary>Gets the alcohol-parity defaults.</summary>
    public static TokenLifetimeConfig Default { get; } =
        new(DefaultAccessLifetime, DefaultRefreshLifetime, DefaultExpirySkew, true);

    /// <summary>Validates and constructs lifetime settings.</summary>
    public static Result<TokenLifetimeConfig, ConfigError> Create(
        TimeSpan access,
        TimeSpan refresh,
        TimeSpan expirySkew,
        bool rotateRefreshTokens)
    {
        if (access <= TimeSpan.Zero)
        {
            return new ConfigError("lifetimes.access", "Access lifetime must be positive.");
        }

        if (refresh <= TimeSpan.Zero)
        {
            return new ConfigError("lifetimes.refresh", "Refresh lifetime must be positive.");
        }

        if (expirySkew < TimeSpan.Zero)
        {
            return new ConfigError("lifetimes.expirySkew", "Expiry skew must not be negative.");
        }

        if (refresh <= access)
        {
            return new ConfigError(
                "lifetimes.refresh",
                "Refresh lifetime must exceed the access lifetime, otherwise refreshing cannot outlive the token it renews.");
        }

        return new TokenLifetimeConfig(access, refresh, expirySkew, rotateRefreshTokens);
    }
}
