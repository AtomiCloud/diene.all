using System.Security.Cryptography;
using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Onboarding;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// In-process doubles for the demo, so it exercises the real surface without an
/// identity provider or a network.
/// </summary>
/// <remarks>
/// These live in <c>App</c> rather than being taken from the shipped TestHelper: the
/// demo consumer models a real service, and a real service does not take a test
/// dependency in production. The TestHelper's equivalents are exercised by the test
/// projects instead.
/// </remarks>
public sealed class DemoRuntime : IDisposable
{
    private readonly RSA _rsa = RSA.Create(2048);
    private readonly JsonWebTokenHandler _handler = new();
    private readonly AuthEngineConfig _config;
    private bool _disposed;

    internal DemoRuntime(AuthEngineConfig config)
    {
        this._config = config;
        this.Clock = new DemoClock(new DateTimeOffset(2026, 1, 1, 12, 0, 0, TimeSpan.Zero));
        this.Backend = new DemoOnboardingBackend();
        this.Client = new DemoCredentialClient(this.Clock);
        this.Validator = new JwtTokenValidator(config, new DemoKeyResolver(this.PublicKey), this.Clock);
        this.Cache = new TokenCache(this.Client, this.Clock, config.Lifetimes);
    }

    /// <summary>Gets the fixed clock the demo runs against.</summary>
    public IAuthClock Clock { get; }

    /// <summary>Gets the in-memory onboarding backend.</summary>
    public IOnboardingBackend Backend { get; }

    /// <summary>Gets the in-memory credential client.</summary>
    public ICredentialClient Client { get; }

    /// <summary>Gets a validator trusting this runtime's own key.</summary>
    public ITokenValidator Validator { get; }

    /// <summary>Gets a token cache over the in-memory client.</summary>
    public TokenCache Cache { get; }

    private SecurityKey PublicKey => new RsaSecurityKey(this._rsa.ExportParameters(false)) { KeyId = "demo" };

    /// <summary>Mints a token the demo's own validator accepts.</summary>
    public string MintDemoToken()
    {
        var now = this.Clock.UtcNow;
        return this._handler.CreateToken(new SecurityTokenDescriptor
        {
            Claims = new Dictionary<string, object>(StringComparer.Ordinal)
            {
                ["sub"] = "demo-user",
                ["iss"] = this._config.Logto.Issuer,
                ["aud"] = AuthEngineDemo.DemoAudience,
                ["iat"] = now.ToUnixTimeSeconds(),
                ["nbf"] = now.ToUnixTimeSeconds(),
                ["exp"] = now.AddMinutes(10).ToUnixTimeSeconds(),
                ["scope"] = "notes:read",
                [this._config.HomeLandscapeClaim] = AuthEngineDemo.DemoLandscape,
            },
            SigningCredentials = new SigningCredentials(
                new RsaSecurityKey(this._rsa) { KeyId = "demo" },
                SecurityAlgorithms.RsaSha256),
        });
    }

    /// <inheritdoc />
    public void Dispose()
    {
        if (this._disposed) return;
        this._rsa.Dispose();
        this._disposed = true;
    }

    private sealed class DemoClock(DateTimeOffset now) : IAuthClock
    {
        public DateTimeOffset UtcNow { get; } = now;
    }

    private sealed class DemoKeyResolver(SecurityKey key) : ISigningKeyResolver
    {
        public Task<Result<IReadOnlyList<SecurityKey>, IDomainProblem>> ResolveAsync(
            CancellationToken cancellationToken = default) =>
            Task.FromResult(Result.Ok<IReadOnlyList<SecurityKey>, IDomainProblem>([key]));
    }

    private sealed class DemoOnboardingBackend : IOnboardingBackend
    {
        private readonly Dictionary<string, string> _landscapes = new(StringComparer.Ordinal);

        public string BackendId => "demo-backend";

        public Task<Result<bool, IDomainProblem>> HasUserAsync(
            string subject,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(Result.Ok<bool, IDomainProblem>(this._landscapes.ContainsKey(subject)));
        }

        public Task<Result<Unit, IDomainProblem>> WriteHomeLandscapeAsync(
            string subject,
            string landscape,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            this._landscapes[subject] = landscape;
            return Task.FromResult(Result.Ok<Unit, IDomainProblem>(new Unit()));
        }
    }

    private sealed class DemoCredentialClient(IAuthClock clock) : ICredentialClient
    {
        public Task<Result<TokenResponse, IDomainProblem>> AcquireAsync(
            string resource,
            IReadOnlyList<string> scopes,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(Result.Ok<TokenResponse, IDomainProblem>(
                new TokenResponse($"demo-access-token for {resource} [{string.Join(' ', scopes)}]",
                    clock.UtcNow.AddMinutes(10))));
        }

        public Task<Result<RefreshedTokens, IDomainProblem>> RefreshAsync(
            string refreshToken,
            string resource,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(Result.Ok<RefreshedTokens, IDomainProblem>(new RefreshedTokens(
                new TokenResponse($"demo-access-token-2 for {resource}", clock.UtcNow.AddMinutes(10)),
                $"rotated-from-{refreshToken}")));
        }

        public Task<Result<Unit, IDomainProblem>> RevokeUserSessionsAsync(
            string userId,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            _ = userId;
            return Task.FromResult(Result.Ok<Unit, IDomainProblem>(new Unit()));
        }
    }
}
