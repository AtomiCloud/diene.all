using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Onboarding;
using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.ServerEngine.Mvc;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace AtomiCloud.Diene.ServerEngine.Onboarding;

/// <summary>
/// The server side of OnboardSync: it hosts the published auth-engine onboarding coordinator
/// over HTTP so a client can read its phase and complete its landscape pick.
/// </summary>
/// <remarks>
/// <para>
/// The coordinator, the guard, and the claim name all come from the published auth-engine
/// package; this controller adds only the HTTP wiring. That split is the whole reason
/// server-engine exists as its own package — the onboarding DECISION is auth's, the endpoints
/// are the server's, and neither has to depend on the other's transport.
/// </para>
/// <para>
/// The route is fixed under <c>/internal</c> alongside the webhook receiver, because these are
/// cluster-internal endpoints a client reaches through the service's own gateway rather than a
/// per-service mount a caller has to discover.
/// </para>
/// </remarks>
[Route("internal/onboard-sync")]
public sealed class OnboardSyncController(
    AuthGuard guard,
    AuthEngineConfig auth,
    OnboardingCoordinator coordinator) : AtomiController
{
    private readonly AuthGuard _guard = guard ?? throw new ArgumentNullException(nameof(guard));
    private readonly AuthEngineConfig _auth = auth ?? throw new ArgumentNullException(nameof(auth));

    private readonly OnboardingCoordinator _coordinator =
        coordinator ?? throw new ArgumentNullException(nameof(coordinator));

    /// <summary>Reports which onboarding phase the authenticated caller is in.</summary>
    [HttpGet("phase")]
    public async Task<ActionResult<OnboardSyncPhaseView>> PhaseAsync(CancellationToken cancellationToken)
    {
        var claims = await this.AuthenticateAsync(cancellationToken).ConfigureAwait(false);
        var phase = await this._coordinator
            .ResolvePhaseAsync(claims, cancellationToken)
            .ConfigureAwait(false);

        return this.Resolve(phase.Map(resolved => new OnboardSyncPhaseView(resolved)));
    }

    /// <summary>Writes the caller's picked landscape as their home-landscape claim.</summary>
    [HttpPost("complete")]
    public async Task<ActionResult> CompleteAsync(
        [FromBody] OnboardSyncCompleteRequest? request,
        CancellationToken cancellationToken)
    {
        var claims = await this.AuthenticateAsync(cancellationToken).ConfigureAwait(false);

        // A missing body and a blank landscape are the same caller mistake, so both are routed
        // to the coordinator's own refusal instead of being validated a second time here. One
        // validation point means the HTTP surface cannot drift from the domain rule.
        return await this.ResolveEmptyAsync(
                this._coordinator.CompleteAsync(claims, request?.Landscape ?? string.Empty, cancellationToken))
            .ConfigureAwait(false);
    }

    /// <summary>
    /// Reads a bearer token from the Authorization header. An absent header and a
    /// non-bearer credential are both reported as a malformed token rather than guessed at.
    /// </summary>
    private static string? ReadBearer(HttpRequest request)
    {
        var header = request.Headers.Authorization.ToString();
        if (string.IsNullOrWhiteSpace(header)) return null;

        const string prefix = "Bearer ";
        if (!header.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return null;

        var token = header[prefix.Length..].Trim();
        return string.IsNullOrEmpty(token) ? null : token;
    }

    private async Task<AuthClaims> AuthenticateAsync(CancellationToken cancellationToken)
    {
        var token = ReadBearer(this.Request) ?? throw AuthProblems.MalformedToken().ToException();

        var outcome = await this._guard
            .GuardAsync(token, this._auth.Logto.Issuer, [], cancellationToken)
            .ConfigureAwait(false);

        if (outcome.IsFailure(out var problem)) throw problem.ToException();
        return outcome.Get();
    }
}
