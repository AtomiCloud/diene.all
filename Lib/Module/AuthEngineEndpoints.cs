using System.Text.Json;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.AuthEngine;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Routing;

namespace AtomiCloud.Diene.AuthEngine.Module;

/// <summary>
/// Maps the auth-engine endpoints under the configured mount path. A consumer enables
/// the module explicitly rather than hand-hosting these routes.
/// </summary>
public static class AuthEngineEndpoints
{
    private static readonly JsonSerializerOptions StrictJson = new()
    {
        PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
    };

    /// <summary>
    /// Maps the handoff endpoints beneath <see cref="HandoffConfig.Mount" />.
    /// </summary>
    /// <remarks>
    /// The mount comes from validated configuration, so a route cannot be built from an
    /// unchecked string. Failures are raised as <see cref="DomainProblemException" /> —
    /// the published Problems package's own supported route — so the handler that package
    /// registers renders them as RFC 9457, and this library's error surface stays
    /// identical to every other Diene service's. Writing the problem into
    /// <c>HttpContext.Items</c> directly is not available: that key is internal to the
    /// Problems package by design.
    /// </remarks>
    public static IEndpointRouteBuilder MapAtomiAuthEngine(
        this IEndpointRouteBuilder endpoints,
        AuthEngineConfig config)
    {
        ArgumentNullException.ThrowIfNull(endpoints);
        ArgumentNullException.ThrowIfNull(config);

        var mount = config.Handoff.Mount;

        // Service parameters are marked explicitly. Minimal APIs otherwise infer a
        // complex parameter as a request body and the route fails while it is mapped.
        endpoints.MapPost(
            mount,
            ([FromServices] AuthGuard guard,
                [FromServices] AuthEngineConfig settings,
                [FromServices] IDeferredTokenMinter minter,
                HttpContext context) => HandleMintAsync(context, guard, settings, minter));

        endpoints.MapPost(
            $"{mount}/redeem",
            ([FromServices] IDeferredTokenMinter minter, HttpContext context) =>
                HandleRedeemAsync(context, minter));

        endpoints.MapGet(
            $"{mount}/session",
            ([FromServices] AuthGuard guard, [FromServices] AuthEngineConfig settings, HttpContext context) =>
                HandleSessionAsync(context, guard, settings));

        return endpoints;
    }

    /// <summary>Validates the web session and mints its digest-backed handoff nonce.</summary>
    internal static async Task<DeferredHandoff> HandleMintAsync(
        HttpContext context,
        AuthGuard guard,
        AuthEngineConfig settings,
        IDeferredTokenMinter minter)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(guard);
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(minter);

        SetNoStore(context.Response);

        var token = ReadBearer(context.Request) ?? throw AuthProblems.MalformedToken().ToException();
        var guarded = await guard
            .GuardAsync(token, settings.Logto.Issuer, [], context.RequestAborted)
            .ConfigureAwait(false);
        if (guarded.IsFailure(out var guardFailure)) throw guardFailure.ToException();

        try
        {
            _ = await ReadStrictJson<DeferredMintRequest>(context.Request, context.RequestAborted)
                .ConfigureAwait(false);
        }
        catch (JsonException)
        {
            throw new InvalidJson(
                "The app handoff mint request must be an empty JSON object.",
                "request body").ToException();
        }

        var claims = guarded.Get();
        if (!claims.FindString("email").IsSome(out var email))
        {
            throw AuthProblems.MalformedToken().ToException();
        }

        var minted = await minter
            .Mint(new DeferredPayload(claims.Subject, email), context.RequestAborted)
            .ConfigureAwait(false);
        if (minted.IsFailure(out var failure)) throw failure.ToException();
        return minted.Get();
    }

    /// <summary>Strict-parses a mobile redeem request and exchanges its nonce.</summary>
    internal static async Task<DeferredExchange> HandleRedeemAsync(
        HttpContext context,
        IDeferredTokenMinter minter)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(minter);

        SetNoStore(context.Response);

        DeferredRedeemRequest request;
        try
        {
            request = await ReadStrictJson<DeferredRedeemRequest>(
                    context.Request,
                    context.RequestAborted)
                .ConfigureAwait(false);
        }
        catch (JsonException)
        {
            throw new AppHandoffExpired().ToException();
        }

        if (request.Device is null || request.Device.Platform is not ("android" or "ios"))
        {
            throw new AppHandoffExpired().ToException();
        }

        var exchanged = await minter.Exchange(request.Nonce, context.RequestAborted).ConfigureAwait(false);
        if (exchanged.IsFailure(out _)) throw new AppHandoffExpired().ToException();
        return exchanged.Get();
    }

    /// <summary>
    /// Returns the caller's validated session view, or throws the typed problem so the
    /// Problems pipeline renders it.
    /// </summary>
    internal static async Task<SessionView> HandleSessionAsync(
        HttpContext context,
        AuthGuard guard,
        AuthEngineConfig settings)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(guard);
        ArgumentNullException.ThrowIfNull(settings);

        var token = ReadBearer(context.Request) ?? throw AuthProblems.MalformedToken().ToException();

        var outcome = await guard
            .GuardAsync(token, settings.Logto.Issuer, [], context.RequestAborted)
            .ConfigureAwait(false);

        if (outcome.IsFailure(out var problem)) throw problem.ToException();

        var claims = outcome.Get();
        return new SessionView(claims.Subject, claims.Scopes, claims.ExpiresAt);
    }

    /// <summary>
    /// Reads a bearer token from the Authorization header, returning null when the header
    /// is absent or is not a bearer credential. Anything else is a caller error the route
    /// reports as a malformed token rather than guessing at.
    /// </summary>
    internal static string? ReadBearer(HttpRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);

        var header = request.Headers.Authorization.ToString();
        if (string.IsNullOrWhiteSpace(header)) return null;

        const string prefix = "Bearer ";
        if (!header.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return null;

        var token = header[prefix.Length..].Trim();
        return string.IsNullOrEmpty(token) ? null : token;
    }

    private static async Task<T> ReadStrictJson<T>(HttpRequest request, CancellationToken cancellationToken)
    {
        if (!request.HasJsonContentType()) throw new JsonException("Content-Type must be application/json.");

        var value = await JsonSerializer
            .DeserializeAsync<T>(request.Body, StrictJson, cancellationToken)
            .ConfigureAwait(false);
        return value ?? throw new JsonException("A JSON object is required.");
    }

    private static void SetNoStore(HttpResponse response)
    {
        response.Headers.CacheControl = "no-store";
        response.OnStarting(
            static state =>
            {
                ((HttpResponse)state).Headers.CacheControl = "no-store";
                return Task.CompletedTask;
            },
            response);
    }
}

/// <summary>The session projection returned by the handoff session endpoint.</summary>
/// <param name="Subject">The authenticated subject.</param>
/// <param name="Scopes">The scopes the token grants.</param>
/// <param name="ExpiresAt">When the token stops being usable.</param>
public sealed record SessionView(string Subject, IReadOnlyList<string> Scopes, DateTimeOffset ExpiresAt);
