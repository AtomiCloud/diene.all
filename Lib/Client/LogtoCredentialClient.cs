using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Client;

/// <summary>
/// Logto-backed credential acquisition over the OAuth 2.0 token endpoint and the
/// Management API.
/// </summary>
/// <remarks>
/// Every transport failure is converted into a problem-typed result rather than an
/// exception, so a caller composing this into a Result pipeline never has to guard it
/// with a try/catch to stay total.
/// </remarks>
public sealed class LogtoCredentialClient : ICredentialClient
{
    private readonly HttpClient _http;
    private readonly AuthEngineConfig _config;
    private readonly IAuthClock _clock;

    /// <summary>Creates a client over an injected <see cref="HttpClient" />.</summary>
    public LogtoCredentialClient(HttpClient http, AuthEngineConfig config, IAuthClock clock)
    {
        ArgumentNullException.ThrowIfNull(http);
        ArgumentNullException.ThrowIfNull(config);
        ArgumentNullException.ThrowIfNull(clock);

        this._http = http;
        this._config = config;
        this._clock = clock;
    }

    /// <inheritdoc />
    public async Task<Result<TokenResponse, IDomainProblem>> AcquireAsync(
        string resource,
        IReadOnlyList<string> scopes,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(resource))
        {
            return Result.Err<TokenResponse, IDomainProblem>(AuthProblems.AudienceMismatch());
        }

        var form = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["grant_type"] = "client_credentials",
            ["client_id"] = this._config.Logto.AppId,
            ["client_secret"] = this._config.Logto.AppSecret,
            ["resource"] = resource,
        };

        if (scopes is { Count: > 0 }) form["scope"] = string.Join(' ', scopes);

        var payload = await this.PostFormAsync(this.TokenEndpoint(), form, cancellationToken)
            .ConfigureAwait(false);

        if (payload.IsFailure(out var failure)) return Result.Err<TokenResponse, IDomainProblem>(failure);

        return this.ToTokenResponse(payload.Get());
    }

    /// <inheritdoc />
    public async Task<Result<RefreshedTokens, IDomainProblem>> RefreshAsync(
        string refreshToken,
        string resource,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(refreshToken))
        {
            return Result.Err<RefreshedTokens, IDomainProblem>(AuthProblems.MalformedToken());
        }

        if (string.IsNullOrWhiteSpace(resource))
        {
            return Result.Err<RefreshedTokens, IDomainProblem>(AuthProblems.AudienceMismatch());
        }

        var form = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["grant_type"] = "refresh_token",
            ["client_id"] = this._config.Logto.AppId,
            ["client_secret"] = this._config.Logto.AppSecret,
            ["refresh_token"] = refreshToken,
            ["resource"] = resource,
        };

        var payload = await this.PostFormAsync(this.TokenEndpoint(), form, cancellationToken)
            .ConfigureAwait(false);

        if (payload.IsFailure(out var failure)) return Result.Err<RefreshedTokens, IDomainProblem>(failure);

        var body = payload.Get();
        var access = this.ToTokenResponse(body);
        if (access.IsFailure(out var accessFailure))
        {
            return Result.Err<RefreshedTokens, IDomainProblem>(accessFailure);
        }

        // With rotation on, the response carries a replacement. When the IdP declines to
        // rotate, the presented token remains current — falling back to it keeps the
        // caller's stored credential correct instead of blanking it.
        var rotated = string.IsNullOrWhiteSpace(body.RefreshToken) ? refreshToken : body.RefreshToken;

        return Result.Ok<RefreshedTokens, IDomainProblem>(new RefreshedTokens(access.Get(), rotated));
    }

    /// <inheritdoc />
    public async Task<Result<Unit, IDomainProblem>> RevokeUserSessionsAsync(
        string userId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            return Result.Err<Unit, IDomainProblem>(AuthProblems.MalformedToken());
        }

        var management = this._config.Logto.Management;
        var form = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["grant_type"] = "client_credentials",
            ["client_id"] = management.ClientId,
            ["client_secret"] = management.ClientSecret,
            ["resource"] = management.Resource,
        };

        var token = await this.PostFormAsync(this.TokenEndpoint(), form, cancellationToken)
            .ConfigureAwait(false);

        if (token.IsFailure(out var tokenFailure)) return Result.Err<Unit, IDomainProblem>(tokenFailure);

        var accessToken = token.Get().AccessToken;
        if (string.IsNullOrWhiteSpace(accessToken))
        {
            return Result.Err<Unit, IDomainProblem>(AuthProblems.MalformedToken());
        }

        var revoke = new Uri(
            management.Endpoint,
            $"api/users/{Uri.EscapeDataString(userId)}/sessions");

        using var request = new HttpRequestMessage(HttpMethod.Delete, revoke);
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue(
            "Bearer",
            accessToken);

        try
        {
            using var response = await this._http.SendAsync(request, cancellationToken).ConfigureAwait(false);
            return response.IsSuccessStatusCode
                ? Result.Ok<Unit, IDomainProblem>(new Unit())
                : Result.Err<Unit, IDomainProblem>(FromStatus(response.StatusCode));
        }
        catch (HttpRequestException)
        {
            return Result.Err<Unit, IDomainProblem>(AuthProblems.IdentityProviderUnreachable());
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Result.Err<Unit, IDomainProblem>(AuthProblems.IdentityProviderUnreachable());
        }
    }

    private Uri TokenEndpoint() => new(this._config.Logto.Endpoint, "oidc/token");

    private async Task<Result<LogtoTokenPayload, IDomainProblem>> PostFormAsync(
        Uri endpoint,
        Dictionary<string, string> form,
        CancellationToken cancellationToken)
    {
        try
        {
            using var content = new FormUrlEncodedContent(form);
            using var response = await this._http
                .PostAsync(endpoint, content, cancellationToken)
                .ConfigureAwait(false);

            if (!response.IsSuccessStatusCode)
            {
                return Result.Err<LogtoTokenPayload, IDomainProblem>(FromStatus(response.StatusCode));
            }

            var payload = await response.Content
                .ReadFromJsonAsync<LogtoTokenPayload>(cancellationToken)
                .ConfigureAwait(false);

            return payload is null
                ? Result.Err<LogtoTokenPayload, IDomainProblem>(AuthProblems.MalformedToken())
                : Result.Ok<LogtoTokenPayload, IDomainProblem>(payload);
        }
        catch (HttpRequestException)
        {
            return Result.Err<LogtoTokenPayload, IDomainProblem>(AuthProblems.IdentityProviderUnreachable());
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Result.Err<LogtoTokenPayload, IDomainProblem>(AuthProblems.IdentityProviderUnreachable());
        }
        catch (System.Text.Json.JsonException)
        {
            return Result.Err<LogtoTokenPayload, IDomainProblem>(AuthProblems.MalformedToken());
        }
    }

    private Result<TokenResponse, IDomainProblem> ToTokenResponse(LogtoTokenPayload payload)
    {
        if (string.IsNullOrWhiteSpace(payload.AccessToken))
        {
            return Result.Err<TokenResponse, IDomainProblem>(AuthProblems.MalformedToken());
        }

        // A missing or non-positive expires_in falls back to the configured access
        // lifetime rather than being treated as "already expired", which would make the
        // cache re-acquire on every single call.
        var seconds = payload.ExpiresIn > 0
            ? TimeSpan.FromSeconds(payload.ExpiresIn)
            : this._config.Lifetimes.Access;

        return Result.Ok<TokenResponse, IDomainProblem>(
            new TokenResponse(payload.AccessToken, this._clock.UtcNow + seconds));
    }

    private static IDomainProblem FromStatus(System.Net.HttpStatusCode status) => status switch
    {
        System.Net.HttpStatusCode.Unauthorized => AuthProblems.InvalidClientCredentials(),
        System.Net.HttpStatusCode.Forbidden => AuthProblems.MissingScopes([], []),
        _ => AuthProblems.IdentityProviderRejected(
            ((int)status).ToString(CultureInfo.InvariantCulture)),
    };

    private sealed record LogtoTokenPayload
    {
        [JsonPropertyName("access_token")]
        public string? AccessToken { get; init; }

        [JsonPropertyName("refresh_token")]
        public string? RefreshToken { get; init; }

        [JsonPropertyName("expires_in")]
        public int ExpiresIn { get; init; }

        [JsonPropertyName("token_type")]
        public string? TokenType { get; init; }
    }
}
