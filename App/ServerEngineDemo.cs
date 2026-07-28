using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Module;
using AtomiCloud.Diene.AuthEngine.Onboarding;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.ServerEngine.Config;
using AtomiCloud.Diene.ServerEngine.Module;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using AuthConfigError = AtomiCloud.Diene.AuthEngine.Config.ConfigError;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// The demo consumer: the composition a real Diene service performs, and nothing else.
/// </summary>
/// <remarks>
/// The order below is the order a service must use. Problems first, because the
/// exception-to-Problem filter resolves the catalog and the type-URI builder the moment it
/// renders anything; the server engine second, because it adds the MVC filter and application
/// part; auth-engine third, for the OnboardSync endpoints' guard. Composing them the other way
/// round fails at the first request rather than at startup, which is why it is spelled out here.
/// </remarks>
public static class ServerEngineDemo
{
    /// <summary>The landscape the demo reports as its own.</summary>
    public const string DemoLandscape = "lapras";

    /// <summary>Builds the engine-owned configuration block the demo runs with.</summary>
    public static Result<ServerEngineConfig, ServerEngineConfigError> BuildConfig(string version)
    {
        var identity = ServiceIdentityConfig.Create(DemoLandscape, "sulfoxide", "demo", "api", version);
        if (identity.IsFailure(out var identityError)) return identityError;

        var webhooks = WebhookConfig.Create(TimeSpan.FromMinutes(2));
        if (webhooks.IsFailure(out var webhookError)) return webhookError;

        return ServerEngineConfig.Create(identity.Get(), webhooks.Get());
    }

    /// <summary>Builds the auth-engine configuration the OnboardSync endpoints validate against.</summary>
    public static Result<AuthEngineConfig, AuthConfigError> BuildAuthConfig()
    {
        var management = LogtoManagementConfig.Create(
            "https://idp.demo.invalid",
            "https://idp.demo.invalid/api",
            "demo-management",
            "demo-management-secret");
        if (management.IsFailure(out var managementError)) return managementError;

        var logto = LogtoConfig.Create(
            "https://idp.demo.invalid",
            "https://idp.demo.invalid/oidc",
            "demo-app",
            "demo-app-secret",
            management.Get());
        if (logto.IsFailure(out var logtoError)) return logtoError;

        return AuthEngineConfig.Create(
            logto.Get(),
            HandoffConfig.Default,
            TokenLifetimeConfig.Default,
            "home_landscape");
    }

    /// <summary>
    /// Composes the demo host on an ephemeral loopback port, with the handler instance the
    /// caller can inspect afterwards.
    /// </summary>
    public static WebApplication BuildApp(
        ServerEngineConfig config,
        AuthEngineConfig auth,
        DemoWebhookHandler handler)
    {
        ArgumentNullException.ThrowIfNull(config);
        ArgumentNullException.ThrowIfNull(auth);
        ArgumentNullException.ThrowIfNull(handler);

        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.SetMinimumLevel(LogLevel.Warning);

        builder.Services.AddAtomiProblems(
            new ProblemIdentity(
                config.Identity.Landscape,
                config.Identity.Platform,
                config.Identity.Service,
                config.Identity.Module),
            new ErrorPortalOption { Scheme = "https", Host = "errors.demo.invalid" },
            catalog => catalog.AddBaseline());

        builder.Services.AddAtomiServerEngine(config);
        builder.Services.AddAtomiWebhookSecrets(DemoDelivery.Secret);
        builder.Services.AddSingleton<IWebhookHandler>(handler);

        // The clock is registered BEFORE auth-engine, whose own registration is a TryAdd, so
        // one clock governs both token expiry and webhook freshness. Two clocks would make a
        // freshness rejection look like skew on mercury's side.
        builder.Services.TryAddSingleton<IAuthClock>(SystemAuthClock.Instance);
        builder.Services.AddAtomiAuthEngine(auth);
        builder.Services.AddSingleton<IOnboardingBackend, DemoOnboardingBackend>();
        builder.Services.AddSingleton<OnboardingCoordinator>();

        var app = builder.Build();
        app.MapControllers();
        return app;
    }

    /// <summary>Names the controllers the shipped package mounts.</summary>
    public static string DescribeControllers() =>
        "server engine mounted: " +
        string.Join(", ", ServerEngineServiceCollectionExtensions.ShippedControllers.Select(type => type.Name));

    /// <summary>Names the providers a receiver will accept deliveries for.</summary>
    public static string DescribeProviders(WebhookHandlerRegistry registry)
    {
        ArgumentNullException.ThrowIfNull(registry);
        return $"webhook providers: {string.Join(", ", registry.Providers.Order(StringComparer.Ordinal))}";
    }

    /// <summary>Reports the contract bounds the receiver enforces.</summary>
    public static string DescribeWebhookWindow(ServerEngineConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);
        return $"webhook window: {config.Webhooks.Tolerance.TotalSeconds:F0}s of a permitted " +
               $"{WebhookConfig.MaximumTolerance.TotalSeconds:F0}s, block '{ServerEngineConfig.Key}', " +
               $"default {WebhookConfig.Default.Tolerance.TotalSeconds:F0}s";
    }
}
