namespace AtomiCloud.Diene.AuthEngine.Client;

/// <summary>An acquired access token and the instant it stops being usable.</summary>
/// <param name="Token">The compact-serialization access token.</param>
/// <param name="ExpiresAt">The absolute expiry instant, resolved against the injected clock.</param>
public sealed record TokenResponse(string Token, DateTimeOffset ExpiresAt)
{
    /// <summary>
    /// Whether the token should be renewed at the supplied instant. Renewal is decided
    /// with skew so a token that expires mid-flight is refreshed before it is sent,
    /// rather than after a request has already failed with it.
    /// </summary>
    public bool NeedsRefresh(DateTimeOffset now, TimeSpan skew) => now + skew >= this.ExpiresAt;
}
