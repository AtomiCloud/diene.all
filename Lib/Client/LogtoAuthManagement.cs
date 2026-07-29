using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Client;

/// <summary>Logto Management API implementation of the full auth-management seam.</summary>
public sealed class LogtoAuthManagement : IAuthManagement
{
    private readonly HttpClient _http;
    private readonly AuthEngineConfig _config;

    /// <summary>Creates the adapter over an injected HTTP client and validated engine config.</summary>
    public LogtoAuthManagement(HttpClient http, AuthEngineConfig config)
    {
        ArgumentNullException.ThrowIfNull(http);
        ArgumentNullException.ThrowIfNull(config);

        this._http = http;
        this._config = config;
    }

    /// <inheritdoc />
    public async Task<Result<Option<AuthManagementUser>, IDomainProblem>> GetUser(
        string userId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(userId)) return Invalid<Option<AuthManagementUser>>();

        var bearer = await this.AccessToken(cancellationToken).ConfigureAwait(false);
        if (bearer.IsFailure(out var tokenFailure)) return tokenFailure.ToErr<Option<AuthManagementUser>>();

        using var request = this.Request(
            HttpMethod.Get,
            $"api/users/{Uri.EscapeDataString(userId)}",
            bearer.Get());
        var sent = await this.Send(request, cancellationToken).ConfigureAwait(false);
        if (sent.IsFailure(out var sendFailure)) return sendFailure.ToErr<Option<AuthManagementUser>>();

        using var response = sent.Get();
        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return Result.Ok<Option<AuthManagementUser>, IDomainProblem>(Option.None<AuthManagementUser>());
        }

        if (!response.IsSuccessStatusCode) return FromStatus<Option<AuthManagementUser>>(response.StatusCode);

        var payload = await Read<UserPayload>(response, cancellationToken).ConfigureAwait(false);
        if (payload.IsFailure(out var malformed)) return malformed.ToErr<Option<AuthManagementUser>>();

        var user = payload.Get();
        return Result.Ok<Option<AuthManagementUser>, IDomainProblem>(
            Option.Some(new AuthManagementUser(userId, user.PrimaryEmail, user.IsSuspended)));
    }

    /// <inheritdoc />
    public async Task<Result<string, IDomainProblem>> MintOneTimeToken(
        string email,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(email)) return Invalid<string>();

        var bearer = await this.AccessToken(cancellationToken).ConfigureAwait(false);
        if (bearer.IsFailure(out var tokenFailure)) return tokenFailure.ToErr<string>();

        using var request = this.Request(HttpMethod.Post, "api/one-time-tokens", bearer.Get());
        request.Content = JsonContent.Create(new OneTimeTokenRequest(
            email,
            DeferredTokenMinter.OneTimeTokenExpiresIn,
            new OneTimeTokenContext("SignIn")));

        var sent = await this.Send(request, cancellationToken).ConfigureAwait(false);
        if (sent.IsFailure(out var sendFailure)) return sendFailure.ToErr<string>();

        using var response = sent.Get();
        if (!response.IsSuccessStatusCode) return FromStatus<string>(response.StatusCode);

        var payload = await Read<OneTimeTokenPayload>(response, cancellationToken).ConfigureAwait(false);
        if (payload.IsFailure(out var malformed) || string.IsNullOrWhiteSpace(payload.Get().Token))
        {
            return Result.Err<string, IDomainProblem>(
                malformed ?? AuthProblems.MalformedToken());
        }

        return Result.Ok<string, IDomainProblem>(payload.Get().Token);
    }

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> SetClaim(
        string userId,
        string key,
        string value,
        CancellationToken cancellationToken = default) =>
        this.ChangeClaim(userId, key, value, remove: false, cancellationToken);

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> RemoveClaim(
        string userId,
        string key,
        CancellationToken cancellationToken = default) =>
        this.ChangeClaim(userId, key, null, remove: true, cancellationToken);

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> AssignRole(
        string userId,
        string roleId,
        CancellationToken cancellationToken = default) =>
        this.SendMutation(
            userId,
            roleId,
            HttpMethod.Post,
            $"api/users/{Uri.EscapeDataString(userId)}/roles",
            new RoleIds([roleId]),
            cancellationToken);

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> RemoveRole(
        string userId,
        string roleId,
        CancellationToken cancellationToken = default) =>
        this.SendMutation(
            userId,
            roleId,
            HttpMethod.Delete,
            $"api/users/{Uri.EscapeDataString(userId)}/roles/{Uri.EscapeDataString(roleId)}",
            null,
            cancellationToken);

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> DeleteUser(
        string userId,
        CancellationToken cancellationToken = default) =>
        this.SendMutation(
            userId,
            null,
            HttpMethod.Delete,
            $"api/users/{Uri.EscapeDataString(userId)}",
            null,
            cancellationToken);

    private async Task<Result<Unit, IDomainProblem>> ChangeClaim(
        string userId,
        string key,
        string? value,
        bool remove,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(userId) || string.IsNullOrWhiteSpace(key) ||
            (!remove && string.IsNullOrWhiteSpace(value)))
        {
            return Invalid<Unit>();
        }

        var bearer = await this.AccessToken(cancellationToken).ConfigureAwait(false);
        if (bearer.IsFailure(out var tokenFailure)) return tokenFailure.ToErr<Unit>();

        var customData = await this.ReadCustomData(userId, bearer.Get(), cancellationToken).ConfigureAwait(false);
        if (customData.IsFailure(out var readFailure)) return readFailure.ToErr<Unit>();

        var updated = customData.Get();
        if (remove)
        {
            updated.Remove(key);
        }
        else
        {
            updated[key] = JsonSerializer.SerializeToElement(value);
        }

        using var request = this.Request(
            HttpMethod.Patch,
            $"api/users/{Uri.EscapeDataString(userId)}/custom-data",
            bearer.Get());
        request.Content = JsonContent.Create(new CustomDataEnvelope(updated));
        return await this.CompleteMutation(request, cancellationToken).ConfigureAwait(false);
    }

    private async Task<Result<Dictionary<string, JsonElement>, IDomainProblem>> ReadCustomData(
        string userId,
        string bearer,
        CancellationToken cancellationToken)
    {
        using var request = this.Request(
            HttpMethod.Get,
            $"api/users/{Uri.EscapeDataString(userId)}/custom-data",
            bearer);
        var sent = await this.Send(request, cancellationToken).ConfigureAwait(false);
        if (sent.IsFailure(out var sendFailure)) return sendFailure.ToErr<Dictionary<string, JsonElement>>();

        using var response = sent.Get();
        if (!response.IsSuccessStatusCode) return FromStatus<Dictionary<string, JsonElement>>(response.StatusCode);

        return await Read<Dictionary<string, JsonElement>>(response, cancellationToken).ConfigureAwait(false);
    }

    private async Task<Result<Unit, IDomainProblem>> SendMutation(
        string userId,
        string? secondaryId,
        HttpMethod method,
        string path,
        object? body,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(userId) ||
            (secondaryId is not null && string.IsNullOrWhiteSpace(secondaryId)))
        {
            return Invalid<Unit>();
        }

        var bearer = await this.AccessToken(cancellationToken).ConfigureAwait(false);
        if (bearer.IsFailure(out var tokenFailure)) return tokenFailure.ToErr<Unit>();

        using var request = this.Request(method, path, bearer.Get());
        if (body is not null) request.Content = JsonContent.Create(body);
        return await this.CompleteMutation(request, cancellationToken).ConfigureAwait(false);
    }

    private async Task<Result<Unit, IDomainProblem>> CompleteMutation(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var sent = await this.Send(request, cancellationToken).ConfigureAwait(false);
        if (sent.IsFailure(out var sendFailure)) return sendFailure.ToErr<Unit>();

        using var response = sent.Get();
        return response.IsSuccessStatusCode
            ? Result.Ok<Unit, IDomainProblem>(new Unit())
            : FromStatus<Unit>(response.StatusCode);
    }

    private async Task<Result<string, IDomainProblem>> AccessToken(CancellationToken cancellationToken)
    {
        var management = this._config.Logto.Management;
        var form = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["grant_type"] = "client_credentials",
            ["client_id"] = management.ClientId,
            ["client_secret"] = management.ClientSecret,
            ["resource"] = management.Resource,
            ["scope"] = "all",
        };

        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            new Uri(this._config.Logto.Endpoint, "oidc/token"))
        {
            Content = new FormUrlEncodedContent(form),
        };
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        var sent = await this.Send(request, cancellationToken).ConfigureAwait(false);
        if (sent.IsFailure(out var sendFailure)) return sendFailure.ToErr<string>();

        using var response = sent.Get();
        if (!response.IsSuccessStatusCode) return FromStatus<string>(response.StatusCode);

        var payload = await Read<AccessTokenPayload>(response, cancellationToken).ConfigureAwait(false);
        if (payload.IsFailure(out var malformed) || string.IsNullOrWhiteSpace(payload.Get().AccessToken))
        {
            return Result.Err<string, IDomainProblem>(malformed ?? AuthProblems.MalformedToken());
        }

        return Result.Ok<string, IDomainProblem>(payload.Get().AccessToken);
    }

    private HttpRequestMessage Request(HttpMethod method, string path, string bearer)
    {
        var request = new HttpRequestMessage(method, new Uri(this._config.Logto.Management.Endpoint, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        return request;
    }

    private async Task<Result<HttpResponseMessage, IDomainProblem>> Send(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        try
        {
            return Result.Ok<HttpResponseMessage, IDomainProblem>(
                await this._http.SendAsync(request, cancellationToken).ConfigureAwait(false));
        }
        catch (HttpRequestException)
        {
            return Result.Err<HttpResponseMessage, IDomainProblem>(AuthProblems.IdentityProviderUnreachable());
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Result.Err<HttpResponseMessage, IDomainProblem>(AuthProblems.IdentityProviderUnreachable());
        }
    }

    private static async Task<Result<T, IDomainProblem>> Read<T>(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        try
        {
            var payload = await response.Content.ReadFromJsonAsync<T>(cancellationToken).ConfigureAwait(false);
            return payload is null ? Invalid<T>() : Result.Ok<T, IDomainProblem>(payload);
        }
        catch (JsonException)
        {
            return Invalid<T>();
        }
    }

    private static Result<T, IDomainProblem> FromStatus<T>(HttpStatusCode status) =>
        Result.Err<T, IDomainProblem>(status switch
        {
            HttpStatusCode.Unauthorized => AuthProblems.InvalidClientCredentials(),
            HttpStatusCode.Forbidden => AuthProblems.MissingScopes([], []),
            _ => AuthProblems.IdentityProviderRejected(((int)status).ToString(System.Globalization.CultureInfo.InvariantCulture)),
        });

    private static Result<T, IDomainProblem> Invalid<T>() =>
        Result.Err<T, IDomainProblem>(AuthProblems.MalformedToken());

    // Serialized by System.Text.Json; the properties are intentionally write-only here.
    // ReSharper disable NotAccessedPositionalProperty.Local
    private sealed record OneTimeTokenRequest(
        [property: JsonPropertyName("email")] string Email,
        [property: JsonPropertyName("expiresIn")] int ExpiresIn,
        [property: JsonPropertyName("context")] OneTimeTokenContext Context);
    // ReSharper restore NotAccessedPositionalProperty.Local

    // ReSharper disable once NotAccessedPositionalProperty.Local
    private sealed record OneTimeTokenContext(
        [property: JsonPropertyName("interactionEvent")] string InteractionEvent);

    // ReSharper disable once NotAccessedPositionalProperty.Local
    private sealed record RoleIds([property: JsonPropertyName("roleIds")] IReadOnlyList<string> Values);

    // ReSharper disable once NotAccessedPositionalProperty.Local
    private sealed record CustomDataEnvelope(
        [property: JsonPropertyName("customData")] IReadOnlyDictionary<string, JsonElement> CustomData);

    // Constructed by System.Text.Json rather than an explicit new expression.
    // ReSharper disable once ClassNeverInstantiated.Local
    private sealed class AccessTokenPayload
    {
        [JsonPropertyName("access_token")]
        public string AccessToken { get; init; } = string.Empty;
    }

    // Constructed by System.Text.Json rather than an explicit new expression.
    // ReSharper disable once ClassNeverInstantiated.Local
    private sealed class UserPayload
    {
        [JsonPropertyName("primaryEmail")]
        [JsonRequired]
        // ReSharper disable once UnusedAutoPropertyAccessor.Local
        public string? PrimaryEmail { get; init; }

        [JsonPropertyName("isSuspended")]
        [JsonRequired]
        // ReSharper disable once UnusedAutoPropertyAccessor.Local
        public bool IsSuspended { get; init; }
    }

    // Constructed by System.Text.Json rather than an explicit new expression.
    // ReSharper disable once ClassNeverInstantiated.Local
    private sealed class OneTimeTokenPayload
    {
        [JsonPropertyName("token")]
        public string Token { get; init; } = string.Empty;
    }
}
