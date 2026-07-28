using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Onboarding;
using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.TestHelper.Builders;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.ServerEngine.Module;
using AtomiCloud.Diene.ServerEngine.Onboarding;
using AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.UnitTest.Hosting;

public class OnboardSyncController_Routes : IDisposable
{
    private const string Audience = "https://idp.test.invalid/oidc";
    private const string HomeClaim = "home_landscape";
    private static readonly DateTimeOffset Now = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);

    private readonly TestTokenIssuer _issuer = new(Audience);

    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task It_should_report_select_landscape_for_a_user_no_backend_knows()
    {
        // Arrange
        await using var host = await this.Host(out _);

        // Act
        var actual = await this.GetPhaseAsync(host);

        // Assert
        actual.Should().Be(OnboardingPhase.SelectLandscape);
    }

    [Fact]
    public async Task It_should_report_awaiting_sync_once_a_backend_knows_the_user()
    {
        // Arrange
        await using var host = await this.Host(out var backend);
        backend.WithKnownUser("user-1");

        // Act
        var actual = await this.GetPhaseAsync(host);

        // Assert
        actual.Should().Be(OnboardingPhase.AwaitingSync);
    }

    [Fact]
    public async Task It_should_report_complete_without_asking_a_backend_when_the_claim_is_present()
    {
        // Arrange — claims-first: a present claim costs no backend round trip.
        await using var host = await this.Host(out var backend);

        // Act
        var actual = await this.GetPhaseAsync(host, landscape: "lapras");

        // Assert
        actual.Should().Be(OnboardingPhase.Complete);
        backend.WrittenLandscapes.Should().BeEmpty();
    }

    [Fact]
    public async Task It_should_write_the_snake_case_phase_name_on_the_wire()
    {
        // Arrange — an ordinal is a renumbering away from meaning something else to a client
        // that has not been redeployed.
        await using var host = await this.Host(out _);
        var request = this.Authorized(HttpMethod.Get, "/internal/onboard-sync/phase");

        // Act
        var actual = await (await host.Client.SendAsync(request, Ct)).Content.ReadAsStringAsync(Ct);

        // Assert
        actual.Should().Be("""{"phase":"select_landscape"}""");
    }

    [Fact]
    public async Task It_should_write_the_picked_landscape_as_the_home_claim()
    {
        // Arrange
        await using var host = await this.Host(out var backend);
        var request = this.Authorized(HttpMethod.Post, "/internal/onboard-sync/complete");
        request.Content = JsonContent.Create(new OnboardSyncCompleteRequest("lapras"));

        // Act
        var actual = await host.Client.SendAsync(request, Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.NoContent);
        backend.WrittenLandscapes.Should().ContainKey("user-1").WhoseValue.Should().Be("lapras");
    }

    [Theory]
    [ClassData(typeof(BlankLandscapeCases))]
    public async Task It_should_refuse_a_pick_with_no_landscape_through_the_domain_rule(string? landscape)
    {
        // Arrange — a missing body and a blank landscape are the same caller mistake, and both
        // are answered by the coordinator's own refusal rather than a second validation here.
        await using var host = await this.Host(out _);
        var request = this.Authorized(HttpMethod.Post, "/internal/onboard-sync/complete");
        request.Content = JsonContent.Create(new OnboardSyncCompleteRequest(landscape));

        // Act
        var actual = await host.Client.SendAsync(request, Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        await actual.Should().BeRfc9457();
    }

    [Fact]
    public async Task It_should_refuse_a_pick_with_no_body_at_all()
    {
        // Arrange
        await using var host = await this.Host(out _);
        var request = this.Authorized(HttpMethod.Post, "/internal/onboard-sync/complete");
        request.Content = new StringContent("null", Encoding.UTF8, "application/json");

        // Act
        var actual = await host.Client.SendAsync(request, Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Theory]
    [ClassData(typeof(MissingBearerCases))]
    public async Task It_should_answer_401_when_no_bearer_credential_is_presented(string? authorization)
    {
        // Arrange
        await using var host = await this.Host(out _);
        var request = new HttpRequestMessage(HttpMethod.Get, "/internal/onboard-sync/phase");
        if (authorization is not null) request.Headers.TryAddWithoutValidation("Authorization", authorization);

        // Act
        var actual = await host.Client.SendAsync(request, Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        await actual.Should().BeRfc9457();
    }

    [Fact]
    public async Task It_should_answer_401_for_a_token_the_guard_rejects()
    {
        // Arrange
        await using var host = await this.Host(out _);
        var request = new HttpRequestMessage(HttpMethod.Get, "/internal/onboard-sync/phase");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", "not-a-jwt");

        // Act
        var actual = await host.Client.SendAsync(request, Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task It_should_answer_401_on_the_complete_route_for_an_unauthenticated_caller()
    {
        // Arrange
        await using var host = await this.Host(out _);
        var request = new HttpRequestMessage(HttpMethod.Post, "/internal/onboard-sync/complete")
        {
            Content = JsonContent.Create(new OnboardSyncCompleteRequest("lapras")),
        };

        // Act
        var actual = await host.Client.SendAsync(request, Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task It_should_surface_a_backend_failure_as_its_own_typed_problem()
    {
        // Arrange
        await using var host = await this.Host(out var backend);
        backend.ProbeFailure = new AtomiCloud.Diene.Problems.Catalog.EntityConflict(
            "Backend is mid-migration.",
            typeof(OnboardSyncController_Routes));

        // Act
        var request = this.Authorized(HttpMethod.Get, "/internal/onboard-sync/phase");
        var actual = await host.Client.SendAsync(request, Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    /// <inheritdoc />
    public void Dispose() => this._issuer.Dispose();

    private static JsonSerializerOptions WireOptions()
    {
        // The client reads with the SAME published contract the server writes with, so the
        // round trip is proven rather than re-implemented in the test.
        var options = new JsonSerializerOptions();
        ServerEngineServiceCollectionExtensions.ApplyWireContract(options);
        return options;
    }

    private async Task<OnboardingPhase> GetPhaseAsync(ServerEngineTestHost host, string? landscape = null)
    {
        var request = this.Authorized(HttpMethod.Get, "/internal/onboard-sync/phase", landscape);
        var response = await host.Client.SendAsync(request, Ct);
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await response.Content.ReadFromJsonAsync<OnboardSyncPhaseView>(WireOptions(), Ct))!.Phase;
    }

    private HttpRequestMessage Authorized(HttpMethod method, string path, string? landscape = null)
    {
        var claims = landscape is null
            ? null
            : new Dictionary<string, object>(StringComparer.Ordinal) { [HomeClaim] = landscape };

        var token = this._issuer.MintValidFor("user-1", Audience, Now, TimeSpan.FromMinutes(10), null, claims);
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    private Task<ServerEngineTestHost> Host(out FakeOnboardingBackend backend)
    {
        var created = new FakeOnboardingBackend();
        backend = created;
        var config = AuthConfig();

        return ServerEngineTestHost.StartAsync(options =>
        {
            options.Now = Now;
            options.Services = services =>
            {
                services.AddSingleton(config);
                services.AddSingleton(this._issuer.KeyResolver);
                services.AddSingleton<ITokenValidator, JwtTokenValidator>();
                services.AddSingleton<AuthGuard>();
                services.AddSingleton<IOnboardingBackend>(created);
                services.AddSingleton<OnboardingCoordinator>();
            };
        });
    }

    private static AuthEngineConfig AuthConfig()
    {
        var management = LogtoManagementConfig
            .Create("https://idp.test.invalid", "https://idp.test.invalid/api", "mgmt", "mgmt-secret")
            .Get();
        var logto = LogtoConfig
            .Create("https://idp.test.invalid", Audience, "app", "app-secret", management)
            .Get();
        return AuthEngineConfig.Create(logto, HandoffConfig.Default, TokenLifetimeConfig.Default, HomeClaim).Get();
    }

    private sealed class BlankLandscapeCases : TheoryData<string?>
    {
        public BlankLandscapeCases()
        {
            this.Add(null!);
            this.Add(string.Empty);
            this.Add("   ");
        }
    }

    private sealed class MissingBearerCases : TheoryData<string?>
    {
        public MissingBearerCases()
        {
            this.Add(null!);
            this.Add(string.Empty);
            this.Add("   ");
            this.Add("Basic dXNlcjpwYXNz");
            this.Add("Bearer");
            this.Add("Bearer    ");
        }
    }
}
