using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.CoreUtils;
using FluentValidation;

namespace AtomiCloud.DotnetBase.App.Options;

/// <summary>
/// The <c>auth:</c> block. Every SSO endpoint, client id, audience, and mount path is
/// configuration (R21) so no identity value is compiled into the service.
/// </summary>
public sealed class AuthOption
{
    /// <summary>Configuration key this block binds to.</summary>
    public const string Key = "Auth";

    /// <summary>Whether the auth engine and its handoff module are wired onto the host.</summary>
    public bool Enabled { get; set; }

    /// <summary>The landscape-local Logto deployment.</summary>
    public LogtoOption Logto { get; set; } = new();

    /// <summary>Deferred-login app-handoff module settings.</summary>
    public HandoffOption Handoff { get; set; } = new();

    /// <summary>Token lifetime and rotation settings.</summary>
    public TokenOption Tokens { get; set; } = new();

    /// <summary>The claim carrying a principal's home landscape.</summary>
    public string HomeLandscapeClaim { get; set; } = "home_landscape";

    /// <summary>The audience this service accepts machine tokens for.</summary>
    public string Audience { get; set; } = string.Empty;
}

/// <summary>The landscape-local Logto deployment this service trusts.</summary>
public sealed class LogtoOption
{
    /// <summary>Logto's base endpoint.</summary>
    public string Endpoint { get; set; } = string.Empty;

    /// <summary>
    /// The OIDC issuer, baked as configuration. It is never read out of the discovery document:
    /// that would hand issuer selection to whoever controls the endpoint.
    /// </summary>
    public string Issuer { get; set; } = string.Empty;

    /// <summary>This service's Logto application id.</summary>
    public string AppId { get; set; } = string.Empty;

    /// <summary>This service's Logto application secret. Blank in YAML, injected per landscape.</summary>
    public string AppSecret { get; set; } = string.Empty;

    /// <summary>Logto Management API settings, used for session revocation.</summary>
    public LogtoManagementOption Management { get; set; } = new();
}

/// <summary>Logto Management API credentials.</summary>
public sealed class LogtoManagementOption
{
    /// <summary>Management API endpoint.</summary>
    public string Endpoint { get; set; } = string.Empty;

    /// <summary>Management API resource indicator.</summary>
    public string Resource { get; set; } = string.Empty;

    /// <summary>Management API client id.</summary>
    public string ClientId { get; set; } = string.Empty;

    /// <summary>Management API client secret. Blank in YAML, injected per landscape.</summary>
    public string ClientSecret { get; set; } = string.Empty;
}

/// <summary>Deferred-login app-handoff module settings.</summary>
public sealed class HandoffOption
{
    /// <summary>Mount path for the enabled auth-engine mint/redeem module.</summary>
    public string Mount { get; set; } = HandoffConfig.DefaultMount;
}

/// <summary>Token lifetime and rotation settings, as ISO 8601 durations.</summary>
public sealed class TokenOption
{
    /// <summary>Access-token lifetime.</summary>
    public string Access { get; set; } = Wire.Format(TokenLifetimeConfig.DefaultAccessLifetime);

    /// <summary>Refresh-token lifetime.</summary>
    public string Refresh { get; set; } = Wire.Format(TokenLifetimeConfig.DefaultRefreshLifetime);

    /// <summary>How far before real expiry the cache renews, so a token never expires mid-flight.</summary>
    public string ExpirySkew { get; set; } = Wire.Format(TokenLifetimeConfig.DefaultExpirySkew);

    /// <summary>
    /// Whether refresh tokens rotate. Rotation is what lets the IdP detect a stolen token.
    /// </summary>
    public bool RotateRefreshTokens { get; set; } = true;
}

/// <summary>Validates <see cref="AuthOption"/> on the final merged configuration layer.</summary>
public sealed class AuthOptionValidator : AbstractValidator<AuthOption>
{
    /// <summary>Declares the block's rules.</summary>
    public AuthOptionValidator()
    {
        this.RuleFor(x => x.HomeLandscapeClaim).NotEmpty();

        this.When(x => x.Enabled, () =>
        {
            this.RuleFor(x => x.Audience)
                .NotEmpty()
                .WithMessage("auth:audience is required when auth is enabled");

            this.RuleFor(x => x.Logto.Endpoint).NotEmpty().Must(BeAnAbsoluteUri)
                .WithMessage("auth:logto:endpoint must be an absolute URI");
            this.RuleFor(x => x.Logto.Issuer).NotEmpty().Must(BeAnAbsoluteUri)
                .WithMessage("auth:logto:issuer must be an absolute URI");
            this.RuleFor(x => x.Logto.AppId).NotEmpty();
            this.RuleFor(x => x.Logto.AppSecret).NotEmpty()
                .WithMessage("auth:logto:app_secret must be injected when auth is enabled");

            this.RuleFor(x => x.Handoff.Mount)
                .NotEmpty()
                .Must(mount => mount.StartsWith('/'))
                .WithMessage("auth:handoff:mount must start with /")
                .Must(mount => !mount.Contains("..", StringComparison.Ordinal))
                .WithMessage("auth:handoff:mount must not contain a traversal segment");
        });

        this.RuleFor(x => x.Tokens.Access).Must(BeAWireDuration)
            .WithMessage("auth:tokens:access must be an ISO 8601 duration");
        this.RuleFor(x => x.Tokens.Refresh).Must(BeAWireDuration)
            .WithMessage("auth:tokens:refresh must be an ISO 8601 duration");
        this.RuleFor(x => x.Tokens.ExpirySkew).Must(BeAWireDuration)
            .WithMessage("auth:tokens:expiry_skew must be an ISO 8601 duration");
    }

    private static bool BeAWireDuration(string value) => Wire.ParseDuration(value).IsSuccess();

    private static bool BeAnAbsoluteUri(string value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var uri) && (uri.Scheme == "http" || uri.Scheme == "https");
}
