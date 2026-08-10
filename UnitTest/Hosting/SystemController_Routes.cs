using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AtomiCloud.Diene.CoreUtils;
using AtomiCloud.Diene.ServerEngine.Mvc;
using AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Hosting;

public class SystemController_Routes
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task It_should_report_the_service_tree_coordinates_and_build_version()
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var actual = await host.Client.GetFromJsonAsync<SystemVersionView>("/system/version", Ct);

        // Assert
        actual!.Landscape.Should().Be("lapras");
        actual.Platform.Should().Be("sulfoxide");
        actual.Service.Should().Be("probe");
        actual.Module.Should().Be("api");
        actual.Version.Should().Be("0.0.0-test");
    }

    [Fact]
    public async Task It_should_report_serving_with_the_instant_it_answered()
    {
        // Arrange
        var now = new DateTimeOffset(2026, 3, 4, 5, 6, 7, TimeSpan.Zero);
        await using var host = await ServerEngineTestHost.StartAsync(options => options.Now = now);

        // Act
        var actual = await host.Client.GetStringAsync("/system/health", Ct);

        // Assert
        actual.Should().Be($$"""{"status":"serving","checkedAt":"{{Wire.Format(now)}}"}""");
    }

    [Fact]
    public async Task It_should_write_the_health_instant_as_an_rfc_3339_utc_string()
    {
        // Arrange — the C0 contract is a string with a Z designator, not a JSON number and not
        // a local offset. A consumer parsing it with a strict RFC 3339 reader is the whole point.
        var now = new DateTimeOffset(2026, 3, 4, 5, 6, 7, TimeSpan.FromHours(8));
        await using var host = await ServerEngineTestHost.StartAsync(options => options.Now = now);

        // Act
        var body = await host.Client.GetStringAsync("/system/health", Ct);
        var stamp = JsonDocument.Parse(body).RootElement.GetProperty("checkedAt").GetString();

        // Assert
        stamp.Should().EndWith("Z");
        Wire.ParseInstant(stamp!).Get().Should().Be(now.ToUniversalTime());
    }

    [Fact]
    public async Task It_should_expose_both_system_routes_at_their_fixed_paths()
    {
        // Arrange — tooling reads these without access to a service's configuration, so the
        // paths are not per-service.
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var version = await host.Client.GetAsync("/system/version", Ct);
        var health = await host.Client.GetAsync("/system/health", Ct);

        // Assert
        version.StatusCode.Should().Be(HttpStatusCode.OK);
        health.StatusCode.Should().Be(HttpStatusCode.OK);
    }
}
