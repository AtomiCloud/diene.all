using System.Net.Http.Headers;
using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.Diene.ApiEngine.Transport;

/// <summary>
/// Attaches a bearer token to every request for ONE upstream, resolved for that upstream's
/// own resource.
/// </summary>
/// <remarks>
/// One handler instance per registered backend is what makes multi-backend safe: the resource
/// is fixed at registration, so there is no shared token and no code path along which one
/// upstream's credential could be sent to another. A shared singleton with a resource
/// parameter would make that mistake possible, and this shape makes it unrepresentable.
/// <para>
/// Token acquisition goes through auth-engine's cache, so a burst of calls performs one
/// acquisition and a token is renewed within skew of expiry rather than after a request has
/// already failed with it.
/// </para>
/// </remarks>
public sealed class AtomiAuthHandler : DelegatingHandler
{
    private readonly TokenCache _tokens;
    private readonly string _resource;
    private readonly IReadOnlyList<string> _scopes;

    /// <summary>Creates a handler bound to one upstream's resource and scopes.</summary>
    public AtomiAuthHandler(TokenCache tokens, string resource, IReadOnlyList<string> scopes)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(resource);
        _tokens = tokens ?? throw new ArgumentNullException(nameof(tokens));
        _resource = resource;
        _scopes = scopes ?? throw new ArgumentNullException(nameof(scopes));
    }

    /// <inheritdoc />
    /// <remarks>
    /// A token failure throws the typed problem rather than sending the request unauthenticated
    /// or inventing a 401. The caller's wrapper unwraps it back into the original problem, so
    /// an IdP outage reads as an authentication failure and not as an unreachable upstream.
    /// </remarks>
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        var token = await _tokens.GetAsync(_resource, _scopes, cancellationToken).ConfigureAwait(false);
        if (token.IsFailure(out var problem)) throw problem.ToException();

        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Get().Token);
        return await base.SendAsync(request, cancellationToken).ConfigureAwait(false);
    }
}
