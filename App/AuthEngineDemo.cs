using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Module;
using AtomiCloud.Diene.AuthEngine.Onboarding;
using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// The demo consumer: how a service composes the auth engine end to end. Kept free of
/// live network calls so it stays runnable and assertable.
/// </summary>
public static class AuthEngineDemo
{
    /// <summary>The resource the demo acquires tokens for.</summary>
    public const string DemoAudience = "https://api.example.invalid";

    /// <summary>The landscape the demo's user belongs to.</summary>
    public const string DemoLandscape = "lapras";

    /// <summary>Builds the in-process doubles the demo runs against.</summary>
    public static DemoRuntime BuildRuntime(AuthEngineConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);
        return new DemoRuntime(config);
    }

    /// <summary>Builds the configuration a service would supply, with the issuer baked in.</summary>
    public static Result<AuthEngineConfig, ConfigError> BuildConfig(string issuer, string endpoint)
    {
        var management = LogtoManagementConfig.Create(
            endpoint,
            "https://default.logto.app/api",
            "management-client",
            "management-secret");

        if (management.IsFailure(out var managementError))
        {
            return Result.Err<AuthEngineConfig, ConfigError>(managementError);
        }

        var logto = LogtoConfig.Create(endpoint, issuer, "demo-app", "demo-secret", management.Get());
        if (logto.IsFailure(out var logtoError)) return Result.Err<AuthEngineConfig, ConfigError>(logtoError);

        // A consumer that wants the default mount takes HandoffConfig.Default; one that
        // configures a mount goes through Create so the path is validated. The demo shows
        // both, and asserts they agree on the default.
        var handoff = HandoffConfig.Create(HandoffConfig.Default.Mount);
        if (handoff.IsFailure(out var handoffError))
        {
            return Result.Err<AuthEngineConfig, ConfigError>(handoffError);
        }

        return AuthEngineConfig.Create(
            logto.Get(),
            handoff.Get(),
            TokenLifetimeConfig.Default,
            "home_landscape");
    }

    /// <summary>
    /// Guards a request the way a controller would: validate the token, then require the
    /// scopes and the home landscape, reporting the first refusal.
    /// </summary>
    public static Task<Result<AuthClaims, IDomainProblem>> GuardRequest(
        ITokenValidator validator,
        AuthEngineConfig config,
        string token,
        string audience,
        string landscape,
        params string[] scopes) =>
        new AuthGuard(validator).GuardAsync(
            token,
            audience,
            [new RequireAllScopes(scopes), new RequireHomeLandscape(config, landscape)]);

    /// <summary>Acquires a service-to-service token through the cache, so renewal is automatic.</summary>
    public static Task<Result<TokenResponse, IDomainProblem>> AcquireServiceToken(
        ICredentialClient client,
        IAuthClock clock,
        AuthEngineConfig config,
        string resource,
        params string[] scopes) =>
        new TokenCache(client, clock, config.Lifetimes).GetAsync(resource, scopes);

    /// <summary>Resolves where a signed-in user sits in the home-landscape onboarding machine.</summary>
    public static Task<Result<OnboardingPhase, IDomainProblem>> ResolveOnboarding(
        AuthEngineConfig config,
        IOnboardingBackend backend,
        AuthClaims claims) =>
        new OnboardingCoordinator(config, backend).ResolvePhaseAsync(claims);

    /// <summary>Renders an auth outcome as the line a demo would print.</summary>
    public static string Describe(Result<AuthClaims, IDomainProblem> outcome) =>
        outcome.Match(
            claims => $"authorized {claims.Subject} with scopes [{string.Join(", ", claims.Scopes)}]" +
                      $", issued {claims.IssuedAt:O}, issuer {claims.Issuer}" +
                      $", audiences [{string.Join(", ", claims.Audiences)}]",
            problem => $"refused ({problem.Id}): {problem.Detail}");

    /// <summary>Renders the configured token lifecycle, including whether refresh rotates.</summary>
    public static string DescribeLifetimes(AuthEngineConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);

        var custom = TokenLifetimeConfig.Create(
            config.Lifetimes.Access,
            config.Lifetimes.Refresh,
            config.Lifetimes.ExpirySkew,
            config.Lifetimes.RotateRefreshTokens);

        return custom.Match(
            lifetimes =>
                $"lifetimes: access {lifetimes.Access}, refresh {lifetimes.Refresh}, " +
                $"skew {lifetimes.ExpirySkew}, rotating {lifetimes.RotateRefreshTokens}",
            error => $"lifetimes rejected -> {error}");
    }

    /// <summary>Renders the caller's next step for an onboarding phase.</summary>
    public static string DescribeOnboarding(OnboardingPhase phase) => phase switch
    {
        OnboardingPhase.Complete => "onboarding: complete, route to the home landscape",
        OnboardingPhase.SelectLandscape => "onboarding: show the landscape selector",
        OnboardingPhase.AwaitingSync => "onboarding: pick recorded, awaiting the claim",
        _ => $"onboarding: unrecognised phase {phase}",
    };

    /// <summary>Completes onboarding by writing the picked landscape as the home claim.</summary>
    public static Task<Result<Unit, IDomainProblem>> CompleteOnboarding(
        AuthEngineConfig config,
        IOnboardingBackend backend,
        AuthClaims claims,
        string landscape) =>
        new OnboardingCoordinator(config, backend).CompleteAsync(claims, landscape);

    /// <summary>Acquires a token for any one of several accepted scopes.</summary>
    public static Task<Result<AuthClaims, IDomainProblem>> GuardAnyScope(
        ITokenValidator validator,
        string token,
        string audience,
        params string[] scopes) =>
        new AuthGuard(validator).GuardOrAnyAsync(token, audience, scopes);

    /// <summary>Drops every cached token, as a caller must after revoking sessions.</summary>
    public static void ClearCachedTokens(TokenCache cache)
    {
        ArgumentNullException.ThrowIfNull(cache);
        cache.Clear();
    }

    /// <summary>Renders a refreshed token pair, showing the rotated credential to persist.</summary>
    public static string DescribeRefresh(RefreshedTokens refreshed)
    {
        ArgumentNullException.ThrowIfNull(refreshed);
        return $"refreshed: access expires {refreshed.Access.ExpiresAt:O}, " +
               $"store refresh token '{refreshed.RefreshToken}'";
    }

    /// <summary>Revokes every session for a user through the Management API.</summary>
    public static Task<Result<Unit, IDomainProblem>> RevokeSessions(
        ICredentialClient client,
        string userId)
    {
        ArgumentNullException.ThrowIfNull(client);
        return client.RevokeUserSessionsAsync(userId);
    }

    /// <summary>Exchanges a refresh token for a new pair.</summary>
    public static Task<Result<RefreshedTokens, IDomainProblem>> Refresh(
        ICredentialClient client,
        string refreshToken,
        string resource)
    {
        ArgumentNullException.ThrowIfNull(client);
        return client.RefreshAsync(refreshToken, resource);
    }

    /// <summary>Reports whether the backend already knows a subject.</summary>
    public static Task<Result<bool, IDomainProblem>> BackendKnows(
        IOnboardingBackend backend,
        string subject)
    {
        ArgumentNullException.ThrowIfNull(backend);
        return backend.HasUserAsync(subject);
    }

    /// <summary>Renders a session view as a demo line.</summary>
    public static string DescribeSession(SessionView view)
    {
        ArgumentNullException.ThrowIfNull(view);
        return $"session {view.Subject}: scopes [{string.Join(", ", view.Scopes)}], expires {view.ExpiresAt:O}";
    }

    /// <summary>Names the backend a coordinator is wired to.</summary>
    public static string DescribeBackend(IOnboardingBackend backend)
    {
        ArgumentNullException.ThrowIfNull(backend);
        return $"onboarding backend: {backend.BackendId}";
    }
}
