using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ServerEngine.Config;

/// <summary>
/// Validated server-engine configuration: the engine-owned configuration block for the
/// MVC surface this package wires.
/// </summary>
/// <remarks>
/// The block is exported next to the code that reads it, per the family's engine-owned
/// block rule. The config library remains the only merger and validator of the composed
/// root schema; this type validates only its own slice, and returns a typed failure so a
/// misconfigured service fails at composition with an actionable field name.
/// </remarks>
public sealed class ServerEngineConfig
{
    /// <summary>The conventional configuration section key.</summary>
    public const string Key = "ServerEngine";

    private ServerEngineConfig(ServiceIdentityConfig identity, WebhookConfig webhooks)
    {
        this.Identity = identity;
        this.Webhooks = webhooks;
    }

    /// <summary>Gets the coordinates this service reports about itself.</summary>
    public ServiceIdentityConfig Identity { get; }

    /// <summary>Gets the internal webhook receiver settings.</summary>
    public WebhookConfig Webhooks { get; }

    /// <summary>Validates every field and returns a typed failure rather than throwing.</summary>
    public static Result<ServerEngineConfig, ServerEngineConfigError> Create(
        ServiceIdentityConfig? identity,
        WebhookConfig? webhooks)
    {
        if (identity is null) return new ServerEngineConfigError("identity", "Service identity is required.");

        return webhooks is null
            ? new ServerEngineConfigError("webhooks", "Webhook configuration is required.")
            : new ServerEngineConfig(identity, webhooks);
    }
}
