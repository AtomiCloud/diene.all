namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>
/// Supplies the per-platform internal webhook secrets a delivery may be signed with.
/// </summary>
/// <remarks>
/// This is a seam rather than a value so a rotation can take effect without a restart: the
/// verifier reads the collection per request, and C0 requires the digest to be compared
/// against EVERY currently live rotation key. A single-secret parameter would make a rotation
/// a deployment, and deliveries signed with the outgoing key would be rejected in the gap.
/// The secret itself arrives through the ordinary workload ExternalSecret path; nothing here
/// knows or cares where it came from.
/// </remarks>
public interface IWebhookSecretProvider
{
    /// <summary>Gets every currently live signing key, in no particular order.</summary>
    IReadOnlyList<string> SigningKeys { get; }
}

/// <summary>
/// A provider over a fixed key set, for a service whose secret is materialized once at
/// composition.
/// </summary>
public sealed class StaticWebhookSecretProvider : IWebhookSecretProvider
{
    /// <summary>Creates a provider over the supplied keys, rejecting a blank or empty set.</summary>
    /// <remarks>
    /// Refusing at composition is deliberate. A receiver with no key cannot verify any
    /// delivery, so every request would 401 — a failure that looks like a signing mismatch on
    /// mercury's side and would be diagnosed there instead of here.
    /// </remarks>
    public StaticWebhookSecretProvider(params string[] keys)
    {
        ArgumentNullException.ThrowIfNull(keys);

        var live = keys.Where(key => !string.IsNullOrWhiteSpace(key)).ToArray();
        if (live.Length == 0)
        {
            throw new ArgumentException("At least one non-blank webhook signing key is required.", nameof(keys));
        }

        this.SigningKeys = live;
    }

    /// <inheritdoc />
    public IReadOnlyList<string> SigningKeys { get; }
}
