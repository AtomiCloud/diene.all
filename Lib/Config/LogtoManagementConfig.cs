using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Config;

/// <summary>Logto Management API settings, used for <c>revokeUserSessions</c>.</summary>
public sealed class LogtoManagementConfig
{
    private LogtoManagementConfig(Uri endpoint, string resource, string clientId, string clientSecret)
    {
        this.Endpoint = endpoint;
        this.Resource = resource;
        this.ClientId = clientId;
        this.ClientSecret = clientSecret;
    }

    /// <summary>Gets the Management API origin.</summary>
    public Uri Endpoint { get; }

    /// <summary>Gets the API resource indicator requested for management tokens.</summary>
    public string Resource { get; }

    /// <summary>Gets the management client id.</summary>
    public string ClientId { get; }

    /// <summary>Gets the management client secret.</summary>
    public string ClientSecret { get; }

    /// <summary>Validates and constructs the Management API settings.</summary>
    public static Result<LogtoManagementConfig, ConfigError> Create(
        string? endpoint,
        string? resource,
        string? clientId,
        string? clientSecret)
    {
        var origin = ConfigValidation.CanonicalOrigin("logto.management.endpoint", endpoint);
        if (origin.IsFailure(out var originError)) return originError;

        if (string.IsNullOrWhiteSpace(resource))
        {
            return new ConfigError("logto.management.resource", "Management resource must not be blank.");
        }

        if (string.IsNullOrWhiteSpace(clientId))
        {
            return new ConfigError("logto.management.clientId", "Management client id must not be blank.");
        }

        if (string.IsNullOrWhiteSpace(clientSecret))
        {
            return new ConfigError("logto.management.clientSecret", "Management client secret must not be blank.");
        }

        return new LogtoManagementConfig(origin.Get(), resource.Trim(), clientId.Trim(), clientSecret);
    }
}
