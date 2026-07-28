using System.Globalization;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace AtomiCloud.Diene.AuthEngine.Tokens;

/// <summary>
/// Validates Logto-compatible JWTs against the build-time issuer.
/// </summary>
/// <remarks>
/// The issuer is taken from configuration rather than from the token or a discovery
/// document, so a token minted by another issuer cannot validate no matter what it
/// claims about itself.
/// </remarks>
public sealed class JwtTokenValidator : ITokenValidator
{
    private readonly AuthEngineConfig _config;
    private readonly ISigningKeyResolver _keys;
    private readonly IAuthClock _clock;
    private readonly JsonWebTokenHandler _handler = new();

    /// <summary>Creates a validator over the supplied configuration, key source, and clock.</summary>
    public JwtTokenValidator(AuthEngineConfig config, ISigningKeyResolver keys, IAuthClock clock)
    {
        ArgumentNullException.ThrowIfNull(config);
        ArgumentNullException.ThrowIfNull(keys);
        ArgumentNullException.ThrowIfNull(clock);

        this._config = config;
        this._keys = keys;
        this._clock = clock;
    }

    /// <inheritdoc />
    public async Task<Result<AuthClaims, IDomainProblem>> ValidateAsync(
        string token,
        string audience,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            return Result.Err<AuthClaims, IDomainProblem>(AuthProblems.MalformedToken());
        }

        if (string.IsNullOrWhiteSpace(audience))
        {
            return Result.Err<AuthClaims, IDomainProblem>(AuthProblems.AudienceMismatch());
        }

        var keys = await this._keys.ResolveAsync(cancellationToken).ConfigureAwait(false);
        if (keys.IsFailure(out var keyFailure)) return Result.Err<AuthClaims, IDomainProblem>(keyFailure);

        var parameters = new TokenValidationParameters
        {
            ValidIssuer = this._config.Logto.Issuer,
            ValidateIssuer = true,
            ValidAudience = audience,
            ValidateAudience = true,
            IssuerSigningKeys = keys.Get(),
            ValidateIssuerSigningKey = true,

            // The handler's own lifetime check reads the MACHINE clock, which would make
            // an expiry verdict depend on the host rather than on the instant the caller
            // injected. It is disabled here and performed below against IAuthClock.
            // Supplying a custom LifetimeValidator is not equivalent: returning false from
            // one collapses every lifetime failure into a single generic exception, so
            // "expired" and "not valid yet" become indistinguishable to the caller.
            ValidateLifetime = false,
        };

        var outcome = await this._handler
            .ValidateTokenAsync(token, parameters)
            .ConfigureAwait(false);

        if (!outcome.IsValid) return Result.Err<AuthClaims, IDomainProblem>(Classify(outcome.Exception));

        var claims = Read(outcome.SecurityToken);
        if (claims.IsFailure(out var unreadable)) return Result.Err<AuthClaims, IDomainProblem>(unreadable);

        return this.CheckLifetime(claims.Get(), outcome.SecurityToken);
    }

    /// <summary>
    /// Applies the configured skew symmetrically around the injected instant, reporting
    /// expiry and not-yet-valid as the distinct failures they are.
    /// </summary>
    private Result<AuthClaims, IDomainProblem> CheckLifetime(AuthClaims claims, SecurityToken securityToken)
    {
        var now = this._clock.UtcNow;
        var skew = this._config.Lifetimes.ExpirySkew;

        if (claims.IsExpired(now, skew))
        {
            return Result.Err<AuthClaims, IDomainProblem>(AuthProblems.ExpiredToken());
        }

        if (securityToken.ValidFrom != DateTime.MinValue)
        {
            var start = new DateTimeOffset(DateTime.SpecifyKind(securityToken.ValidFrom, DateTimeKind.Utc));
            if (now + skew < start)
            {
                return Result.Err<AuthClaims, IDomainProblem>(AuthProblems.TokenNotYetValid());
            }
        }

        return Result.Ok<AuthClaims, IDomainProblem>(claims);
    }

    /// <summary>
    /// Maps a validation exception onto a specific problem. Each arm names a distinct
    /// cause so a caller can tell an expired token from an untrusted issuer; anything
    /// unrecognised falls back to the least-specific authentication failure rather than
    /// being reported as something it might not be.
    /// </summary>
    private static IDomainProblem Classify(Exception? exception) => exception switch
    {
        // Measured against Microsoft.IdentityModel.Tokens 8.21.0 rather than assumed: these
        // are siblings under SecurityTokenValidationException, with exactly one real
        // parent/child pair — SecurityTokenSignatureKeyNotFoundException derives from
        // SecurityTokenInvalidSignatureException, so it must be matched first.
        SecurityTokenExpiredException => AuthProblems.ExpiredToken(),
        SecurityTokenNotYetValidException => AuthProblems.TokenNotYetValid(),
        SecurityTokenInvalidLifetimeException => AuthProblems.ExpiredToken(),
        SecurityTokenInvalidIssuerException => AuthProblems.IssuerMismatch(),
        SecurityTokenInvalidAudienceException => AuthProblems.AudienceMismatch(),
        SecurityTokenSignatureKeyNotFoundException => AuthProblems.InvalidSignature(),
        SecurityTokenInvalidSignatureException => AuthProblems.InvalidSignature(),
        _ => AuthProblems.MalformedToken(),
    };

    /// <summary>Projects a validated token into the closed claims view.</summary>
    private static Result<AuthClaims, IDomainProblem> Read(SecurityToken securityToken)
    {
        if (securityToken is not JsonWebToken jwt)
        {
            return Result.Err<AuthClaims, IDomainProblem>(AuthProblems.MalformedToken());
        }

        var subject = jwt.Subject;
        if (string.IsNullOrWhiteSpace(subject))
        {
            return Result.Err<AuthClaims, IDomainProblem>(AuthProblems.MalformedToken());
        }

        var claims = jwt.Claims
            .GroupBy(claim => claim.Type, StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group => group.Count() == 1
                    ? (object?)group.First().Value
                    : group.Select(claim => claim.Value).ToArray(),
                StringComparer.Ordinal);

        return new AuthClaims(
            subject,
            jwt.Issuer,
            [.. jwt.Audiences],
            Scopes.Parse(FindClaim(claims, "scope")),
            jwt.IssuedAt == DateTime.MinValue
                ? DateTimeOffset.MinValue
                : new DateTimeOffset(DateTime.SpecifyKind(jwt.IssuedAt, DateTimeKind.Utc)),
            new DateTimeOffset(DateTime.SpecifyKind(jwt.ValidTo, DateTimeKind.Utc)),
            claims);
    }

    private static string? FindClaim(IReadOnlyDictionary<string, object?> claims, string name) =>
        claims.TryGetValue(name, out var value)
            ? value switch
            {
                string text => text,
                string[] many => string.Join(' ', many),
                not null => Convert.ToString(value, CultureInfo.InvariantCulture),
                _ => null,
            }
            : null;
}
