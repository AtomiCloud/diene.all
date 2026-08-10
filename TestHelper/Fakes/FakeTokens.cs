using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;

namespace AtomiCloud.Diene.ApiEngine.TestHelper.Fakes;

/// <summary>
/// Assembles the token source a registered backend's auth handler reads from, over
/// auth-engine's own credential fake.
/// </summary>
/// <remarks>
/// No fake credential client is shipped here. auth-engine already publishes one, and a second
/// implementation of the same port would drift from the contract it is meant to imitate — which
/// is the failure mode a shared fake exists to prevent. This helper only saves a consumer the
/// three-line assembly of cache, clock, and lifetimes.
/// </remarks>
public static class FakeTokens
{
    /// <summary>Builds a token cache over a scripted credential client and a driven clock.</summary>
    public static TokenCache Cache(FakeCredentialClient credentials, FakeAuthClock clock) =>
        new(credentials, clock, TokenLifetimeConfig.Default);

    /// <summary>
    /// Builds a token cache that hands out one long-lived token per resource, for tests whose
    /// subject is the client tree rather than token lifetime.
    /// </summary>
    /// <remarks>
    /// The token embeds the resource it was minted for, which is what lets a multi-backend test
    /// assert that each backend received ITS OWN credential — a constant token would make a
    /// cross-backend leak invisible.
    /// </remarks>
    public static TokenCache Cache(params string[] resources)
    {
        ArgumentNullException.ThrowIfNull(resources);

        var clock = new FakeAuthClock();
        var credentials = new FakeCredentialClient();
        foreach (var resource in resources)
        {
            credentials.ScriptToken(resource, TokenFor(resource), clock.UtcNow.AddHours(1));
        }

        return Cache(credentials, clock);
    }

    /// <summary>The token <see cref="Cache(string[])" /> mints for a resource.</summary>
    public static string TokenFor(string resource) => $"fake-token-for-{resource}";
}
