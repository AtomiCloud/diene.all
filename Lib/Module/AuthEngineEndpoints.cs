using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
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

        var group = endpoints.MapGroup(config.Handoff.Mount);

        // AuthGuard and the config are marked [FromServices] explicitly. Minimal APIs
        // otherwise infer a complex parameter as a request BODY, which throws at map time
        // on a GET — the route would never even be registered.
        group.MapGet(
            "/session",
            ([FromServices] AuthGuard guard, [FromServices] AuthEngineConfig settings, HttpContext context) =>
                HandleSessionAsync(context, guard, settings));

        return endpoints;
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
}

/// <summary>The session projection returned by the handoff session endpoint.</summary>
/// <param name="Subject">The authenticated subject.</param>
/// <param name="Scopes">The scopes the token grants.</param>
/// <param name="ExpiresAt">When the token stops being usable.</param>
public sealed record SessionView(string Subject, IReadOnlyList<string> Scopes, DateTimeOffset ExpiresAt);
