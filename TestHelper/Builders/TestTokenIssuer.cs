using System.Globalization;
using System.Security.Cryptography;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace AtomiCloud.Diene.AuthEngine.TestHelper.Builders;

/// <summary>
/// Mints real, signed JWTs for tests, together with the matching public key.
/// </summary>
/// <remarks>
/// This issues genuinely signed tokens rather than hand-assembled strings, so a test
/// exercises the real signature path. A fake that skipped signing would let a validator
/// with its signature check disabled pass every test — the failure the check exists to
/// prevent would be invisible to the suite meant to catch it.
/// </remarks>
public sealed class TestTokenIssuer : IDisposable
{
    private readonly RSA _rsa = RSA.Create(2048);
    private readonly JsonWebTokenHandler _handler = new();
    private readonly string _keyId;
    private bool _disposed;

    /// <summary>Creates an issuer for the supplied issuer identifier.</summary>
    public TestTokenIssuer(string issuer = "https://idp.test.invalid", string keyId = "test-key")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(issuer);
        ArgumentException.ThrowIfNullOrWhiteSpace(keyId);

        this.Issuer = issuer;
        this._keyId = keyId;
    }

    /// <summary>Gets the issuer identifier stamped into every minted token.</summary>
    public string Issuer { get; }

    /// <summary>Gets the public key a validator should trust.</summary>
    public SecurityKey PublicKey =>
        new RsaSecurityKey(this._rsa.ExportParameters(false)) { KeyId = this._keyId };

    /// <summary>Gets a key resolver serving this issuer's public key.</summary>
    public ISigningKeyResolver KeyResolver => new FakeSigningKeyResolver(this.PublicKey);

    /// <summary>
    /// Gets the credentials this issuer signs with, for minting a token whose shape
    /// <see cref="Mint" /> deliberately refuses — a missing subject, say. Without these a
    /// test would have to sign with an untrusted key, and the token would then fail on
    /// the SIGNATURE rather than on the defect under test: a pass for the wrong reason.
    /// </summary>
    public SigningCredentials SigningCredentials =>
        new(new RsaSecurityKey(this._rsa) { KeyId = this._keyId }, SecurityAlgorithms.RsaSha256);

    /// <summary>
    /// Mints a signed token. Every temporal input is explicit so a test states the exact
    /// lifetime it means to exercise rather than inheriting the machine clock.
    /// </summary>
    public string Mint(
        string subject,
        string audience,
        DateTimeOffset issuedAt,
        DateTimeOffset expiresAt,
        IEnumerable<string>? scopes = null,
        IReadOnlyDictionary<string, object>? extraClaims = null,
        DateTimeOffset? notBefore = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(subject);
        ArgumentException.ThrowIfNullOrWhiteSpace(audience);

        var claims = new Dictionary<string, object>(StringComparer.Ordinal)
        {
            ["sub"] = subject,
            ["iss"] = this.Issuer,
            ["aud"] = audience,
            ["iat"] = ToUnix(issuedAt),
            ["exp"] = ToUnix(expiresAt),
            ["nbf"] = ToUnix(notBefore ?? issuedAt),
            ["jti"] = Guid.NewGuid().ToString("N", CultureInfo.InvariantCulture),
        };

        var scopeList = scopes?.Where(scope => !string.IsNullOrWhiteSpace(scope)).ToArray() ?? [];
        if (scopeList.Length > 0) claims["scope"] = string.Join(' ', scopeList);

        if (extraClaims is not null)
        {
            foreach (var (key, value) in extraClaims) claims[key] = value;
        }

        var signing = new SigningCredentials(
            new RsaSecurityKey(this._rsa) { KeyId = this._keyId },
            SecurityAlgorithms.RsaSha256);

        return this._handler.CreateToken(new SecurityTokenDescriptor
        {
            Claims = claims,
            SigningCredentials = signing,
        });
    }

    /// <summary>Mints a token that is valid for the supplied span from the given instant.</summary>
    public string MintValidFor(
        string subject,
        string audience,
        DateTimeOffset now,
        TimeSpan lifetime,
        IEnumerable<string>? scopes = null,
        IReadOnlyDictionary<string, object>? extraClaims = null) =>
        this.Mint(subject, audience, now, now + lifetime, scopes, extraClaims);

    /// <inheritdoc />
    public void Dispose()
    {
        if (this._disposed) return;
        this._rsa.Dispose();
        this._disposed = true;
    }

    private static long ToUnix(DateTimeOffset instant) => instant.ToUnixTimeSeconds();
}
