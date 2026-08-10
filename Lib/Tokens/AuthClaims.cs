using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Tokens;

/// <summary>
/// A validated token's claims. Construction is closed to the library so a value of this
/// type is evidence that validation ran, rather than a bag a caller can assert into.
/// </summary>
public sealed class AuthClaims
{
    private readonly IReadOnlyDictionary<string, object?> _claims;

    internal AuthClaims(
        string subject,
        string issuer,
        IReadOnlyList<string> audiences,
        IReadOnlyList<string> scopes,
        DateTimeOffset issuedAt,
        DateTimeOffset expiresAt,
        IReadOnlyDictionary<string, object?> claims)
    {
        this.Subject = subject;
        this.Issuer = issuer;
        this.Audiences = audiences;
        this.Scopes = scopes;
        this.IssuedAt = issuedAt;
        this.ExpiresAt = expiresAt;
        this._claims = claims;
    }

    /// <summary>Gets the <c>sub</c> claim.</summary>
    public string Subject { get; }

    /// <summary>Gets the <c>iss</c> claim, already checked against the baked-in issuer.</summary>
    public string Issuer { get; }

    /// <summary>Gets the <c>aud</c> claim values.</summary>
    public IReadOnlyList<string> Audiences { get; }

    /// <summary>Gets the granted scopes, split from the space-delimited <c>scope</c> claim.</summary>
    public IReadOnlyList<string> Scopes { get; }

    /// <summary>Gets the <c>iat</c> instant.</summary>
    public DateTimeOffset IssuedAt { get; }

    /// <summary>Gets the <c>exp</c> instant.</summary>
    public DateTimeOffset ExpiresAt { get; }

    /// <summary>Reads an arbitrary claim, absent rather than null when it is not present.</summary>
    public Option<object?> Find(string name) =>
        !string.IsNullOrWhiteSpace(name) && this._claims.TryGetValue(name, out var value)
            ? Option.Some(value)
            : Option.None<object?>();

    /// <summary>Reads a claim as a non-blank string, absent when missing, null, or blank.</summary>
    public Option<string> FindString(string name)
    {
        if (!this.Find(name).IsSome(out var raw)) return Option.None<string>();

        return raw switch
        {
            string text when !string.IsNullOrWhiteSpace(text) => Option.Some(text),
            _ => Option.None<string>(),
        };
    }

    /// <summary>Whether the token has expired at the supplied instant, allowing for skew.</summary>
    public bool IsExpired(DateTimeOffset now, TimeSpan skew) => now - skew >= this.ExpiresAt;
}
