using System.Net;
using System.Net.Http.Json;
using AtomiCloud.DotnetBase.App.Modules.Info;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.IntTest.Api;

/// <summary>
/// The info endpoint through real routing. It is what BOTH probes target, so a regression here is
/// a rollout that never becomes ready — and it must answer without touching a dependency, which
/// is exactly what a host with no containers behind it proves.
/// </summary>
public class Info_Endpoint : IAsyncLifetime
{
    private readonly ServiceHost _host = new();

    private HttpClient _client = null!;

    public ValueTask InitializeAsync()
    {
        this._client = this._host.CreateClient();
        return ValueTask.CompletedTask;
    }

    public async ValueTask DisposeAsync()
    {
        this._client?.Dispose();
        await this._host.DisposeAsync();
    }

    [Fact]
    public async Task It_should_answer_the_root_route_with_the_service_identity()
    {
        // Act
        var response = await this._client.GetAsync("/", TestContext.Current.CancellationToken);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var view = await response.Content.ReadFromJsonAsync<InfoView>(TestContext.Current.CancellationToken);
        view.Should().NotBeNull();
        view!.Service.Should().Be("dotnet-api");
        view.Module.Should().Be("api");
        view.Platform.Should().Be("sulfoxide");
        view.Landscape.Should().Be("lapras");
    }

    [Fact]
    public async Task It_should_answer_without_any_dependency_being_reachable()
    {
        // Arrange — this host has no Postgres, no cache and no storage behind it at all.

        // Act
        var response = await this._client.GetAsync("/", TestContext.Current.CancellationToken);

        // Assert — dependency-blind by design: a database blip must never roll the deployment.
        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task It_should_serve_the_note_routes_from_this_assembly_under_a_test_host()
    {
        // Arrange — under a test host the ENTRY assembly is the test project, so a controller in
        // the App assembly 404s unless that assembly is registered as an application part. This
        // asserts the registration HOLDS rather than assuming it: a 404 here would be the trap,
        // and any other status proves the route was found and dispatched.

        // Act
        var response = await this._client.GetAsync("/api/v1/notes", TestContext.Current.CancellationToken);

        // Assert
        response.StatusCode.Should().NotBe(HttpStatusCode.NotFound);
    }
}
