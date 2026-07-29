using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Module;
using AtomiCloud.Diene.Config;
using AtomiCloud.Diene.Otel;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.ServerEngine.Config;
using AtomiCloud.Diene.ServerEngine.Module;
using AtomiCloud.DotnetBase.App.Error;
using AtomiCloud.DotnetBase.App.Options;
using AtomiCloud.DotnetBase.App.StartUp.Registration;

namespace AtomiCloud.DotnetBase.App.StartUp;

/// <summary>
/// The composition root. Registration is layered in a fixed order — logging, options,
/// versioning, controllers, otel, cache, domain, jobs — and each layer is one extension method
/// so a reader can see the whole shape of the service without reading any of them.
/// </summary>
public static class Server
{
    /// <summary>
    /// Composes the web host. Every failure to build a library configuration is surfaced here,
    /// at composition, with the offending field named — never at the first request.
    /// </summary>
    /// <param name="args">The process arguments.</param>
    /// <returns>A built, unstarted application.</returns>
    public static WebApplication Build(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);

        // ── layer 1: configuration ────────────────────────────────────────────────────────
        builder.Configuration.AddServiceConfiguration(landscape: string.Empty);

        // ── layer 2: logging ──────────────────────────────────────────────────────────────
        builder.AddServiceLogging();

        // ── layer 3: options ──────────────────────────────────────────────────────────────
        builder.Services.AddServiceOptions();

        var app = builder.Services.Resolve<AppOption>();
        var portal = builder.Services.Resolve<ErrorPortalOption>();
        var server = builder.Services.Resolve<ServerOption>();
        var auth = builder.Services.Resolve<AuthOption>();
        var http = builder.Services.Resolve<HttpOption>();

        // ── layer 4: observability ────────────────────────────────────────────────────────
        builder.AddServiceTelemetry(app);

        // ── layer 5: problems, then the server stack that renders them ────────────────────
        // Problems FIRST: the exception filter resolves the catalog and the type-URI builder
        // the moment it renders anything, so the wrong order fails at the first error.
        builder.Services.AddAtomiProblems(
            new ProblemIdentity(app.Landscape, app.Platform, app.Service, app.Module),
            portal,
            catalog => catalog.AddServiceProblems());

        builder.Services.AddAtomiServerEngine(BuildServerEngineConfig(app, server));
        builder.Services.AddAtomiWebhookSecrets([.. server.WebhookSigningKeys]);
        builder.Services.AddServiceWebhookHandlers();

        // ── layer 6: auth, including the enabled app-handoff module ───────────────────────
        if (auth.Enabled) builder.Services.AddAtomiAuthEngine(BuildAuthEngineConfig(auth));

        // ── layer 7: versioning and controllers ───────────────────────────────────────────
        builder.Services.AddServiceVersioning();
        builder.Services.AddServiceControllers(http);

        // ── layer 8: cache, persistence, domain, jobs ─────────────────────────────────────
        builder.Services.AddServiceCache();
        builder.Services.AddServicePersistence();
        builder.Services.AddServiceDomain();
        builder.Services.AddServiceJobs();

        return Compose(builder.Build(), http, auth);
    }

    /// <summary>Builds and runs the HTTP server.</summary>
    /// <param name="args">The process arguments.</param>
    /// <returns>The process exit code.</returns>
    public static async Task<int> RunAsync(string[] args)
    {
        await Build(args).RunAsync().ConfigureAwait(false);
        return 0;
    }

    private static WebApplication Compose(WebApplication application, HttpOption http, AuthOption auth)
    {
        if (http.ForwardedHeaders) application.UseForwardedHeaders();

        // One place writes an error response. UseExceptionHandler is what lets the published
        // problems pipeline render RFC 9457 for anything that escapes an action.
        application.UseExceptionHandler();

        if (http.Cors.Enabled) application.UseCors(ControllerRegistration.CorsPolicy);

        application.UseServiceOpenApi(http);
        application.MapControllers();

        // The mint/redeem module is ENABLED, not hand-written: the endpoints ship in the
        // auth engine and mount wherever configuration says.
        if (auth.Enabled) application.MapAtomiAuthEngine(BuildAuthEngineConfig(auth));

        return application;
    }

    private static ServerEngineConfig BuildServerEngineConfig(AppOption app, ServerOption server)
    {
        var identity = ServiceIdentityConfig
            .Create(app.Landscape, app.Platform, app.Service, app.Module, app.Version)
            .Match(value => value, error => throw Invalid("app", error.Field, error.Reason));

        var tolerance = AtomiCloud.Diene.CoreUtils.Wire
            .ParseDuration(server.WebhookTolerance)
            .Match(
                value => value,
                error => throw Invalid("server_engine", "webhook_tolerance", error.ToString()));

        var webhooks = WebhookConfig
            .Create(tolerance)
            .Match(value => value, error => throw Invalid("server_engine", error.Field, error.Reason));

        return ServerEngineConfig
            .Create(identity, webhooks)
            .Match(value => value, error => throw Invalid("server_engine", error.Field, error.Reason));
    }

    private static AuthEngineConfig BuildAuthEngineConfig(AuthOption auth)
    {
        var management = LogtoManagementConfig
            .Create(
                auth.Logto.Management.Endpoint,
                auth.Logto.Management.Resource,
                auth.Logto.Management.ClientId,
                auth.Logto.Management.ClientSecret)
            .Match(value => value, error => throw Invalid("auth", error.Field, error.Reason));

        var logto = LogtoConfig
            .Create(auth.Logto.Endpoint, auth.Logto.Issuer, auth.Logto.AppId, auth.Logto.AppSecret, management)
            .Match(value => value, error => throw Invalid("auth", error.Field, error.Reason));

        var handoff = HandoffConfig
            .Create(auth.Handoff.Mount)
            .Match(value => value, error => throw Invalid("auth", error.Field, error.Reason));

        var lifetimes = TokenLifetimeConfig
            .Create(
                Duration(auth.Tokens.Access, "auth", "tokens:access"),
                Duration(auth.Tokens.Refresh, "auth", "tokens:refresh"),
                Duration(auth.Tokens.ExpirySkew, "auth", "tokens:expiry_skew"),
                auth.Tokens.RotateRefreshTokens)
            .Match(value => value, error => throw Invalid("auth", error.Field, error.Reason));

        return AuthEngineConfig
            .Create(logto, handoff, lifetimes, auth.HomeLandscapeClaim)
            .Match(value => value, error => throw Invalid("auth", error.Field, error.Reason));
    }

    private static TimeSpan Duration(string value, string block, string field) => AtomiCloud.Diene.CoreUtils.Wire
        .ParseDuration(value)
        .Match(parsed => parsed, error => throw Invalid(block, field, error.ToString()));

    private static InvalidOperationException Invalid(string block, string field, string reason) =>
        new($"configuration block '{block}' is invalid at '{field}': {reason}");
}
