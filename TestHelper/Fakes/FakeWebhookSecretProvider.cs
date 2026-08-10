using AtomiCloud.Diene.ServerEngine.Webhooks;

namespace AtomiCloud.Diene.ServerEngine.TestHelper.Fakes;

/// <summary>
/// A secret provider a test drives, including the states the shipped static provider refuses.
/// </summary>
/// <remarks>
/// Rotation is the case worth being able to reach: C0 requires a delivery to verify against
/// every live key, and the only way to prove that is to add a second key and re-sign with the
/// old one. This fake also permits an EMPTY key set, which
/// <see cref="StaticWebhookSecretProvider" /> refuses at construction — a receiver that has lost
/// its secret is a real production state, and a test must be able to reach it.
/// </remarks>
public sealed class FakeWebhookSecretProvider : IWebhookSecretProvider
{
    private readonly List<string> _keys;

    /// <summary>Creates a provider over the supplied keys, which may be none.</summary>
    public FakeWebhookSecretProvider(params string[] keys)
    {
        ArgumentNullException.ThrowIfNull(keys);
        this._keys = [.. keys];
    }

    /// <inheritdoc />
    public IReadOnlyList<string> SigningKeys => this._keys;

    /// <summary>Adds an incoming rotation key while the outgoing one is still live.</summary>
    public FakeWebhookSecretProvider Rotate(string key)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        this._keys.Add(key);
        return this;
    }

    /// <summary>Drops every key, modelling a receiver whose secret failed to materialize.</summary>
    public FakeWebhookSecretProvider Forget()
    {
        this._keys.Clear();
        return this;
    }
}
