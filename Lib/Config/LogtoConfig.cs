using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Config;

/// <summary>Logto identity-provider settings, including the build-time issuer.</summary>
public sealed class LogtoConfig
{
    private LogtoConfig(Uri endpoint, string issuer, string appId, string appSecret, LogtoManagementConfig management)
    {
        this.Endpoint = endpoint;
        this.Issuer = issuer;
        this.AppId = appId;
        this.AppSecret = appSecret;
        this.Management = management;
    }

    /// <summary>Gets the canonical Logto origin.</summary>
    public Uri Endpoint { get; }

    /// <summary>
    /// Gets the OIDC issuer baked in at build time. Token validation compares against
    /// this value, never against an issuer read from a discovery document.
    /// </summary>
    public string Issuer { get; }

    /// <summary>Gets the application client id.</summary>
    public string AppId { get; }

    /// <summary>Gets the application client secret.</summary>
    public string AppSecret { get; }

    /// <summary>Gets the Management API settings used for session revocation.</summary>
    public LogtoManagementConfig Management { get; }

    /// <summary>Validates and constructs the Logto settings.</summary>
    public static Result<LogtoConfig, ConfigError> Create(
        string? endpoint,
        string? issuer,
        string? appId,
        string? appSecret,
        LogtoManagementConfig? management)
    {
        var origin = ConfigValidation.CanonicalOrigin("logto.endpoint", endpoint);
        if (origin.IsFailure(out var originError)) return originError;

        if (string.IsNullOrWhiteSpace(issuer))
        {
            return new ConfigError("logto.issuer", "Issuer must not be blank; it is baked in at build time.");
        }

        if (!Uri.TryCreate(issuer.Trim(), UriKind.Absolute, out var issuerUri) ||
            (issuerUri.Scheme != Uri.UriSchemeHttps && issuerUri.Scheme != Uri.UriSchemeHttp))
        {
            return new ConfigError("logto.issuer", "Issuer must be an absolute http or https URI.");
        }

        if (string.IsNullOrWhiteSpace(appId)) return new ConfigError("logto.appId", "App id must not be blank.");
        if (string.IsNullOrWhiteSpace(appSecret))
        {
            return new ConfigError("logto.appSecret", "App secret must not be blank.");
        }

        if (management is null)
        {
            return new ConfigError("logto.management", "Management configuration is required.");
        }

        return new LogtoConfig(origin.Get(), issuer.Trim(), appId.Trim(), appSecret, management);
    }
}
