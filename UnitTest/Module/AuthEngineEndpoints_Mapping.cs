using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Module;
using FluentAssertions;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.UnitTest.Module;

/// <summary>
/// Covers the route wiring itself: that the module mounts where configuration says and
/// nowhere else.
/// </summary>
public class AuthEngineEndpoints_Mapping
{
    private static WebApplication Host()
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseSetting("urls", "http://127.0.0.1:0");
        return builder.Build();
    }

    [Fact]
    public void One_mapping_call_mounts_mint_redeem_and_session_at_the_default_path()
    {
        using var app = Host();

        app.MapAtomiAuthEngine(AuthEngineFixture.Config()).Should().NotBeNull();

        RoutePatterns(app).Should().BeEquivalentTo(
            ["/app-handoff", "/app-handoff/redeem", "/app-handoff/session"],
            options => options.WithStrictOrdering());
    }

    [Fact]
    public void Mounts_beneath_a_custom_mount_path()
    {
        // The mount is configurable, so the route must follow configuration rather than a
        // constant baked into the mapping.
        using var app = Host();

        var management = LogtoManagementConfig.Create(
            "https://idp.test.invalid",
            "https://idp.test.invalid/api",
            "client",
            "secret").Get();
        var logto = LogtoConfig.Create(
            "https://idp.test.invalid",
            AuthEngineFixture.Issuer,
            "app",
            "secret",
            management).Get();
        var config = AuthEngineConfig.Create(
            logto,
            HandoffConfig.Create("/auth/handoff").Get(),
            TokenLifetimeConfig.Default,
            "home_landscape").Get();

        app.MapAtomiAuthEngine(config);

        RoutePatterns(app).Should().BeEquivalentTo(
            ["/auth/handoff", "/auth/handoff/redeem", "/auth/handoff/session"],
            options => options.WithStrictOrdering());
    }

    /// <summary>
    /// Reads route patterns from the builder's own data sources. The application-level
    /// <see cref="EndpointDataSource" /> is only populated once the host builds its
    /// endpoint graph, so reading it here returns an empty set rather than the routes
    /// that were just mapped.
    /// </summary>
    private static IReadOnlyList<string> RoutePatterns(WebApplication app) =>
    [
        .. ((IEndpointRouteBuilder)app).DataSources
            .SelectMany(source => source.Endpoints)
            .OfType<RouteEndpoint>()
            .Select(endpoint => endpoint.RoutePattern.RawText!),
    ];

    [Fact]
    public void Rejects_null_mapping_arguments()
    {
        using var app = Host();

        FluentActions.Invoking(() => app.MapAtomiAuthEngine(null!))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() =>
                AuthEngineEndpoints.MapAtomiAuthEngine(null!, AuthEngineFixture.Config()))
            .Should().Throw<ArgumentNullException>();
    }
}
