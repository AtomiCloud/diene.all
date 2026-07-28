using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Module;
using AtomiCloud.Diene.AuthEngine.Onboarding;
using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.Tokens;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// Composition root and demo consumer.
/// </summary>
/// <remarks>
/// This runs every helper it ships rather than declaring them. A demo that merely
/// exposes methods nobody calls is documentation with a compiler attached — and the
/// strict dead-code pass, which excludes test projects, is what makes that visible.
/// </remarks>
public static class Program
{
    /// <summary>Runs the demo and returns a process exit code.</summary>
    public static async Task<int> Main(string[] args)
    {
        _ = args;

        var issuer = Environment.GetEnvironmentVariable("AUTH_ISSUER");
        if (string.IsNullOrWhiteSpace(issuer)) issuer = "https://idp.example.invalid/oidc";

        var endpoint = Environment.GetEnvironmentVariable("AUTH_ENDPOINT");
        if (string.IsNullOrWhiteSpace(endpoint)) endpoint = "https://idp.example.invalid";

        var built = AuthEngineDemo.BuildConfig(issuer, endpoint);
        if (built.IsFailure(out var error))
        {
            Console.WriteLine($"configuration rejected -> {error}");
            return 1;
        }

        var config = built.Get();
        Console.WriteLine(
            $"auth engine ready: issuer {config.Logto.Issuer}, mount {config.Handoff.Mount}");
        Console.WriteLine(AuthEngineDemo.DescribeLifetimes(config));

        var runtime = AuthEngineDemo.BuildRuntime(config);

        Console.WriteLine(AuthEngineDemo.DescribeBackend(runtime.Backend));
        Console.WriteLine(AuthEngineDemo.DescribeOnboarding(OnboardingPhase.SelectLandscape));

        var token = runtime.MintDemoToken();

        var guarded = await AuthEngineDemo.GuardRequest(
            runtime.Validator,
            config,
            token,
            AuthEngineDemo.DemoAudience,
            AuthEngineDemo.DemoLandscape,
            "notes:read").ConfigureAwait(false);
        Console.WriteLine(AuthEngineDemo.Describe(guarded));

        var anyScope = await AuthEngineDemo
            .GuardAnyScope(runtime.Validator, token, AuthEngineDemo.DemoAudience, "notes:write", "notes:read")
            .ConfigureAwait(false);
        Console.WriteLine(AuthEngineDemo.Describe(anyScope));

        if (!guarded.IsSuccess(out var claims)) return 1;

        var phase = await AuthEngineDemo.ResolveOnboarding(config, runtime.Backend, claims).ConfigureAwait(false);
        Console.WriteLine(AuthEngineDemo.DescribeOnboarding(phase.GetOr(OnboardingPhase.SelectLandscape)));

        Console.WriteLine(
            (await AuthEngineDemo.BackendKnows(runtime.Backend, claims.Subject).ConfigureAwait(false))
            .Match(known => $"backend knows {claims.Subject}: {known}", problem => $"probe failed: {problem.Detail}"));

        Console.WriteLine(
            (await AuthEngineDemo
                .CompleteOnboarding(config, runtime.Backend, claims, AuthEngineDemo.DemoLandscape)
                .ConfigureAwait(false))
            .Match(_ => "onboarding synced", problem => $"sync failed: {problem.Detail}"));

        var acquired = await AuthEngineDemo
            .AcquireServiceToken(runtime.Client, runtime.Clock, config, AuthEngineDemo.DemoAudience, "notes:read")
            .ConfigureAwait(false);
        Console.WriteLine(
            acquired.Match(
                t => $"service token '{t.Token}' expires {t.ExpiresAt:O}, " +
                     $"needs refresh now: {t.NeedsRefresh(runtime.Clock.UtcNow, config.Lifetimes.ExpirySkew)}",
                problem => $"acquire failed: {problem.Detail}"));

        Console.WriteLine(
            (await AuthEngineDemo.Refresh(runtime.Client, "rt-1", AuthEngineDemo.DemoAudience).ConfigureAwait(false))
            .Match(AuthEngineDemo.DescribeRefresh, problem => $"refresh failed: {problem.Detail}"));

        Console.WriteLine(
            (await AuthEngineDemo.RevokeSessions(runtime.Client, claims.Subject).ConfigureAwait(false))
            .Match(_ => $"revoked sessions for {claims.Subject}", problem => $"revoke failed: {problem.Detail}"));

        // Revocation must be followed by a cache clear, or the revoked session keeps
        // being served from cache until its tokens age out.
        AuthEngineDemo.ClearCachedTokens(runtime.Cache);
        Console.WriteLine("token cache cleared after revocation");

        Console.WriteLine(AuthEngineDemo.DescribeSession(
            new SessionView(claims.Subject, claims.Scopes, claims.ExpiresAt)));

        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseSetting("urls", "http://127.0.0.1:0");

        // Both calls return their receiver for chaining; the demo consumes the return
        // values so the fluent surface it advertises is one it actually uses.
        var services = builder.Services.AddAtomiAuthEngine(config);
        Console.WriteLine($"registered {services.Count} services");

        using var app = builder.Build();
        var routes = app.MapAtomiAuthEngine(config);
        Console.WriteLine($"mapped {routes.DataSources.Sum(source => source.Endpoints.Count)} endpoint(s)");

        var guard = app.Services.GetRequiredService<AuthGuard>();
        var validator = app.Services.GetRequiredService<ITokenValidator>();
        var cache = app.Services.GetRequiredService<TokenCache>();
        var credentials = app.Services.GetRequiredService<ICredentialClient>();
        Console.WriteLine(
            $"module enabled: {guard.GetType().Name}, {validator.GetType().Name}, " +
            $"{cache.GetType().Name}, {credentials.GetType().Name} at {config.Handoff.Mount}/session");

        runtime.Dispose();
        return 0;
    }
}
