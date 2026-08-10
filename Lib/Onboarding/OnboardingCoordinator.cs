using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Onboarding;

/// <summary>
/// Decides the onboarding phase for a signed-in user and completes it.
/// </summary>
/// <remarks>
/// Claims-first: the home-landscape claim on the validated token is consulted BEFORE the
/// backend is asked anything. That ordering matters — a present claim means the user is
/// onboarded and no backend round trip is owed, so the common path costs nothing.
/// </remarks>
public sealed class OnboardingCoordinator
{
    private readonly AuthEngineConfig _config;
    private readonly IOnboardingBackend _backend;

    /// <summary>Creates a coordinator over configuration and one backend.</summary>
    public OnboardingCoordinator(AuthEngineConfig config, IOnboardingBackend backend)
    {
        ArgumentNullException.ThrowIfNull(config);
        ArgumentNullException.ThrowIfNull(backend);

        this._config = config;
        this._backend = backend;
    }

    /// <summary>Determines which onboarding phase the caller is in.</summary>
    public async Task<Result<OnboardingPhase, IDomainProblem>> ResolvePhaseAsync(
        AuthClaims claims,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(claims);

        if (claims.FindString(this._config.HomeLandscapeClaim).IsSome(out _))
        {
            return Result.Ok<OnboardingPhase, IDomainProblem>(OnboardingPhase.Complete);
        }

        var known = await this._backend
            .HasUserAsync(claims.Subject, cancellationToken)
            .ConfigureAwait(false);

        if (known.IsFailure(out var failure))
        {
            return Result.Err<OnboardingPhase, IDomainProblem>(failure);
        }

        // A backend record without a claim means the pick happened but the sync has not
        // landed; no record at all means the user has not chosen yet. Collapsing these
        // would re-show the selector to a user who already picked.
        return Result.Ok<OnboardingPhase, IDomainProblem>(
            known.Get() ? OnboardingPhase.AwaitingSync : OnboardingPhase.SelectLandscape);
    }

    /// <summary>Writes the picked landscape as the user's home-landscape claim.</summary>
    public async Task<Result<Unit, IDomainProblem>> CompleteAsync(
        AuthClaims claims,
        string landscape,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(claims);

        if (string.IsNullOrWhiteSpace(landscape))
        {
            return Result.Err<Unit, IDomainProblem>(AuthProblems.HomeLandscapeAbsent());
        }

        return await this._backend
            .WriteHomeLandscapeAsync(claims.Subject, landscape.Trim(), cancellationToken)
            .ConfigureAwait(false);
    }
}
