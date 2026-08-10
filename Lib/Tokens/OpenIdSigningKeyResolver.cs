using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace AtomiCloud.Diene.AuthEngine.Tokens;

/// <summary>
/// Resolves signing keys from the issuer's OpenID discovery document, with the caching
/// and refresh behaviour of <see cref="ConfigurationManager{T}" /> so key rotation is
/// picked up without a restart.
/// </summary>
/// <remarks>
/// Only the KEYS are taken from discovery. The issuer itself is never read from the
/// document — it stays the build-time value in configuration — so a compromised or
/// swapped discovery endpoint cannot move trust to another issuer.
/// </remarks>
public sealed class OpenIdSigningKeyResolver : ISigningKeyResolver
{
    private readonly IConfigurationManager<OpenIdConnectConfiguration> _configuration;

    /// <summary>Creates a resolver over the discovery document at the configured Logto origin.</summary>
    public OpenIdSigningKeyResolver(AuthEngineConfig config, HttpClient http)
    {
        ArgumentNullException.ThrowIfNull(config);
        ArgumentNullException.ThrowIfNull(http);

        var metadata = new Uri(config.Logto.Endpoint, "oidc/.well-known/openid-configuration");
        this._configuration = new ConfigurationManager<OpenIdConnectConfiguration>(
            metadata.AbsoluteUri,
            new OpenIdConnectConfigurationRetriever(),
            new HttpDocumentRetriever(http) { RequireHttps = metadata.Scheme == Uri.UriSchemeHttps });
    }

    /// <summary>Creates a resolver over an injected configuration manager.</summary>
    public OpenIdSigningKeyResolver(IConfigurationManager<OpenIdConnectConfiguration> configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        this._configuration = configuration;
    }

    /// <inheritdoc />
    public async Task<Result<IReadOnlyList<SecurityKey>, IDomainProblem>> ResolveAsync(
        CancellationToken cancellationToken = default)
    {
        try
        {
            var configuration = await this._configuration
                .GetConfigurationAsync(cancellationToken)
                .ConfigureAwait(false);

            IReadOnlyList<SecurityKey> keys = [.. configuration.SigningKeys];

            // An empty key set is a could-not-look, not a found-nothing: validating
            // against zero keys would fail every token with a signature error and hide
            // the fact that discovery returned nothing usable.
            return keys.Count == 0
                ? Result.Err<IReadOnlyList<SecurityKey>, IDomainProblem>(
                    AuthProblems.IdentityProviderUnreachable())
                : Result.Ok<IReadOnlyList<SecurityKey>, IDomainProblem>(keys);
        }
        catch (Exception exception) when (exception is HttpRequestException or InvalidOperationException
                                              or System.IO.IOException)
        {
            return Result.Err<IReadOnlyList<SecurityKey>, IDomainProblem>(
                AuthProblems.IdentityProviderUnreachable());
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Result.Err<IReadOnlyList<SecurityKey>, IDomainProblem>(
                AuthProblems.IdentityProviderUnreachable());
        }
    }
}
