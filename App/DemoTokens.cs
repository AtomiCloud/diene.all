using System.Globalization;
using System.Security.Cryptography;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// Mints genuinely signed tokens for the demo and serves the matching public key.
/// </summary>
/// <remarks>
/// This lives in <c>App</c> rather than being taken from a shipped TestHelper, because the demo
/// models a real service and a real service does not take a test dependency in production. The
/// tokens are really signed and really validated: a demo that skipped signing would drive the
/// OnboardSync routes past a validator whose signature check could be disabled without the demo
/// noticing.
/// </remarks>
public sealed class DemoTokens : IDisposable, ISigningKeyResolver
{
    private const string KeyId = "demo-key";

    private readonly RSA _rsa = RSA.Create(2048);
    private readonly JsonWebTokenHandler _handler = new();
    private bool _disposed;

    /// <summary>Gets the public key a validator should trust.</summary>
    public SecurityKey PublicKey => new RsaSecurityKey(this._rsa.ExportParameters(false)) { KeyId = KeyId };

    /// <summary>Mints a signed token for a subject, optionally carrying a home-landscape claim.</summary>
    public string Mint(string subject, string issuer, DateTimeOffset now, string? homeLandscape, string claimName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(subject);
        ArgumentException.ThrowIfNullOrWhiteSpace(issuer);
        ArgumentException.ThrowIfNullOrWhiteSpace(claimName);

        var claims = new Dictionary<string, object>(StringComparer.Ordinal)
        {
            ["sub"] = subject,
            ["iss"] = issuer,
            ["aud"] = issuer,
            ["iat"] = now.ToUnixTimeSeconds(),
            ["nbf"] = now.ToUnixTimeSeconds(),
            ["exp"] = now.AddMinutes(10).ToUnixTimeSeconds(),
            ["jti"] = Guid.NewGuid().ToString("N", CultureInfo.InvariantCulture),
        };

        if (homeLandscape is not null) claims[claimName] = homeLandscape;

        return this._handler.CreateToken(new SecurityTokenDescriptor
        {
            Claims = claims,
            SigningCredentials = new SigningCredentials(
                new RsaSecurityKey(this._rsa) { KeyId = KeyId },
                SecurityAlgorithms.RsaSha256),
        });
    }

    /// <inheritdoc />
    public Task<Result<IReadOnlyList<SecurityKey>, IDomainProblem>> ResolveAsync(
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(Result.Ok<IReadOnlyList<SecurityKey>, IDomainProblem>([this.PublicKey]));
    }

    /// <inheritdoc />
    public void Dispose()
    {
        if (this._disposed) return;
        this._rsa.Dispose();
        this._disposed = true;
    }
}
