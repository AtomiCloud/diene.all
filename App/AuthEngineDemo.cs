using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
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

        var handoff = HandoffConfig.Create(HandoffConfig.DefaultMount);
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
            claims => $"authorized {claims.Subject} with scopes [{string.Join(", ", claims.Scopes)}]",
            problem => $"refused ({problem.Id}): {problem.Detail}");
}
