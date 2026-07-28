using System.Net;
using System.Text;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.ServerEngine.Config;
using AtomiCloud.Diene.ServerEngine.Module;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using AtomiCloud.DotnetBase.App;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace AtomiCloud.DotnetBase.IntTest;

/// <summary>
/// Drives the demo consumer as a real service: a Kestrel host on a loopback port, reached over
/// real HTTP.
/// </summary>
/// <remarks>
/// The unit tier already exercises the same controllers through the in-process test host. This
/// tier exists because a TestServer bypasses the transport, so it cannot show that a real socket,
/// real Kestrel request parsing, and real content negotiation produce the same statuses and the
/// same bytes. For a server library that is the difference worth paying for.
/// </remarks>
public class ServerEngineDemo_Composition : IAsyncLifetime
{
    private readonly DemoWebhookHandler _handler = new();
    private ServerEngineConfig _config = null!;
    private IHost _app = null!;
    private HttpClient _client = null!;

    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    /// <inheritdoc />
    public async ValueTask InitializeAsync()
    {
        this._config = ServerEngineDemo.BuildConfig("1.0.0-int").Get();
        var auth = ServerEngineDemo.BuildAuthConfig().Get();
        this._app = ServerEngineDemo.BuildApp(this._config, auth, this._handler);
        await this._app.StartAsync(Ct);

        var addresses = this._app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>();
        this._client = new HttpClient { BaseAddress = new Uri(addresses!.Addresses.First(), UriKind.Absolute) };
    }

    /// <inheritdoc />
    public async ValueTask DisposeAsync()
    {
        this._client.Dispose();
        await this._app.StopAsync(CancellationToken.None);
        this._app.Dispose();
    }

    [Fact]
    public async Task It_should_serve_the_system_routes_over_a_real_socket()
    {
        // Act
        var version = await this._client.GetAsync("/system/version", Ct);
        var health = await this._client.GetAsync("/system/health", Ct);

        // Assert
        version.StatusCode.Should().Be(HttpStatusCode.OK);
        (await version.Content.ReadAsStringAsync(Ct)).Should().Contain("\"version\":\"1.0.0-int\"");
        health.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task It_should_resolve_a_consumer_controller_through_the_shared_base()
    {
        // Act
        var found = await this._client.GetAsync("/notes/note-1", Ct);
        var erased = await this._client.DeleteAsync("/notes/note-1/async", Ct);

        // Assert
        found.StatusCode.Should().Be(HttpStatusCode.OK);
        erased.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task It_should_render_a_consumer_problem_as_rfc_9457_over_the_wire()
    {
        // Act
        var actual = await this._client.GetAsync("/notes/absent", Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var envelope = (await actual.Should().BeRfc9457()).Which;
        envelope.Type.Should().Be(
            "https://errors.demo.invalid/docs/lapras/sulfoxide/demo/api/v1/entity_not_found");
    }

    [Fact]
    public async Task It_should_answer_500_for_a_problem_the_consumer_forgot_to_register()
    {
        // Act
        var actual = await this._client.GetAsync("/notes/note-1/unregistered", Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.InternalServerError);
    }

    [Fact]
    public async Task It_should_answer_401_on_onboard_sync_without_a_bearer_token()
    {
        // Act
        var actual = await this._client.GetAsync("/internal/onboard-sync/phase", Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task It_should_process_a_signed_delivery_and_stay_processed_on_redelivery()
    {
        // Arrange — at-least-once means a redelivery must still be 200; the handler's own key set
        // is what stops the work happening twice.
        var now = DateTimeOffset.UtcNow;
        var body = DemoDelivery.Envelope(DemoWebhookHandler.DemoProvider, "int-evt-1", now, 1);

        // Act
        var first = await this._client.SendAsync(
            DemoDelivery.Request(DemoWebhookHandler.DemoProvider, body, now),
            Ct);
        var second = await this._client.SendAsync(
            DemoDelivery.Request(DemoWebhookHandler.DemoProvider, body, now),
            Ct);

        // Assert
        first.StatusCode.Should().Be(HttpStatusCode.OK);
        second.StatusCode.Should().Be(HttpStatusCode.OK);
        this._handler.Seen[WebhookIdempotency.KeyOf(Read(body))].Should().BeGreaterThanOrEqualTo(2);
    }

    [Fact]
    public async Task It_should_answer_421_for_an_event_the_handler_disowns()
    {
        // Arrange
        var now = DateTimeOffset.UtcNow;
        var body = DemoDelivery.Envelope(
            DemoWebhookHandler.DemoProvider,
            DemoWebhookHandler.DisownedEventId,
            now,
            1);

        // Act
        var actual = await this._client.SendAsync(
            DemoDelivery.Request(DemoWebhookHandler.DemoProvider, body, now),
            Ct);

        // Assert
        ((int)actual.StatusCode).Should().Be(WebhookProtocol.NotMineStatus);
    }

    [Fact]
    public async Task It_should_answer_421_for_a_provider_with_no_registered_handler()
    {
        // Arrange
        var now = DateTimeOffset.UtcNow;
        var body = DemoDelivery.Envelope("paypal", "int-evt-2", now, 1);

        // Act
        var actual = await this._client.SendAsync(DemoDelivery.Request("paypal", body, now), Ct);

        // Assert
        ((int)actual.StatusCode).Should().Be(WebhookProtocol.NotMineStatus);
        actual.StatusCode.Should().NotBe(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task It_should_answer_401_for_a_delivery_signed_with_the_wrong_secret()
    {
        // Arrange
        var now = DateTimeOffset.UtcNow;
        var body = DemoDelivery.Envelope(DemoWebhookHandler.DemoProvider, "int-evt-3", now, 1);

        // Act
        var actual = await this._client.SendAsync(
            DemoDelivery.Request(DemoWebhookHandler.DemoProvider, body, now, "not-the-secret"),
            Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task It_should_answer_415_for_a_delivery_sent_as_plain_json()
    {
        // Arrange
        var now = DateTimeOffset.UtcNow;
        var body = DemoDelivery.Envelope(DemoWebhookHandler.DemoProvider, "int-evt-4", now, 1);

        // Act
        var actual = await this._client.SendAsync(
            DemoDelivery.Request(
                DemoWebhookHandler.DemoProvider,
                body,
                now,
                DemoDelivery.Secret,
                "application/json"),
            Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.UnsupportedMediaType);
    }

    [Fact]
    public void It_should_report_what_the_composition_actually_enabled()
    {
        // Act
        var controllers = ServerEngineDemo.DescribeControllers();
        var providers = ServerEngineDemo.DescribeProviders(
            this._app.Services.GetRequiredService<WebhookHandlerRegistry>());
        var window = ServerEngineDemo.DescribeWebhookWindow(this._config);

        // Assert
        controllers.Should().Contain("SystemController").And.Contain("WebhookController")
            .And.Contain("OnboardSyncController");
        providers.Should().Contain(DemoWebhookHandler.DemoProvider);
        window.Should().Contain("120s of a permitted 300s").And.Contain(ServerEngineConfig.Key);
    }

    [Fact]
    public void It_should_describe_every_envelope_field_a_handler_may_rely_on()
    {
        // Arrange
        var envelope = Read(
            DemoDelivery.Envelope(DemoWebhookHandler.DemoProvider, "int-evt-5", DateTimeOffset.UtcNow, 2));

        // Act
        var actual = DemoWebhookHandler.Describe(envelope, 1);

        // Assert
        actual.Should().Contain("v1 stripe/int-evt-5")
            .And.Contain("tenant=tenant-1")
            .And.Contain("attempt=2")
            .And.Contain("headers=[x-demo=one|two]");
    }

    [Fact]
    public void It_should_reject_a_demo_configuration_that_could_not_be_served()
    {
        // Act — a blank version cannot be reported by the system route, so composition refuses it.
        var actual = ServerEngineDemo.BuildConfig("   ");

        // Assert
        actual.GetFailure().Field.Should().Be("identity.version");
        actual.GetFailure().ToString().Should().Contain("identity.version");
    }

    [Fact]
    public void It_should_refuse_to_build_a_host_without_its_parts()
    {
        // Arrange
        var auth = ServerEngineDemo.BuildAuthConfig().Get();

        // Act
        var withoutConfig = () => ServerEngineDemo.BuildApp(null!, auth, this._handler);
        var withoutAuth = () => ServerEngineDemo.BuildApp(this._config, null!, this._handler);
        var withoutHandler = () => ServerEngineDemo.BuildApp(this._config, auth, null!);
        var describeWithoutRegistry = () => ServerEngineDemo.DescribeProviders(null!);
        var windowWithoutConfig = () => ServerEngineDemo.DescribeWebhookWindow(null!);

        // Assert
        withoutConfig.Should().Throw<ArgumentNullException>();
        withoutAuth.Should().Throw<ArgumentNullException>();
        withoutHandler.Should().Throw<ArgumentNullException>();
        describeWithoutRegistry.Should().Throw<ArgumentNullException>();
        windowWithoutConfig.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task It_should_track_the_landscape_an_onboarding_backend_was_told_to_write()
    {
        // Arrange
        var subject = new DemoOnboardingBackend();

        // Act
        var before = await subject.HasUserAsync("user-1", Ct);
        await subject.WriteHomeLandscapeAsync("user-1", ServerEngineDemo.DemoLandscape, Ct);
        var after = await subject.HasUserAsync("user-1", Ct);

        // Assert
        subject.BackendId.Should().Be("demo-backend");
        before.Get().Should().BeFalse();
        after.Get().Should().BeTrue();
        subject.Written["user-1"].Should().Be(ServerEngineDemo.DemoLandscape);
    }

    [Fact]
    public void It_should_sign_a_delivery_the_receiver_accepts_and_refuse_a_null_body()
    {
        // Arrange
        var now = DateTimeOffset.UtcNow;
        var body = DemoDelivery.Envelope(DemoWebhookHandler.DemoProvider, "int-evt-6", now, 1);

        // Act
        var header = DemoDelivery.Signature(now, body, DemoDelivery.Secret);
        var act = () => DemoDelivery.Request(DemoWebhookHandler.DemoProvider, null!, now);

        // Assert
        header.Should().MatchRegex("^t=[0-9]+, v1=[0-9a-f]{64}$");
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task It_should_refuse_a_null_envelope_or_a_cancelled_delivery()
    {
        // Arrange
        var subject = new DemoWebhookHandler();
        using var source = new CancellationTokenSource();
        await source.CancelAsync();

        // Act
        var withoutEnvelope = async () => await subject.HandleAsync(null!, Ct);
        var describeWithoutEnvelope = () => DemoWebhookHandler.Describe(null!, 1);
        var cancelled = async () =>
            await subject.HandleAsync(
                Read(DemoDelivery.Envelope(DemoWebhookHandler.DemoProvider, "x", DateTimeOffset.UtcNow, 1)),
                source.Token);

        // Assert
        await withoutEnvelope.Should().ThrowAsync<ArgumentNullException>();
        describeWithoutEnvelope.Should().Throw<ArgumentNullException>();
        await cancelled.Should().ThrowAsync<OperationCanceledException>();
    }

    [Fact]
    public void It_should_carry_the_note_that_triggered_an_unregistered_problem()
    {
        // Act
        var actual = new DemoUnregisteredProblem("note-7");

        // Assert
        actual.Id.Should().Be("demo_unregistered");
        actual.Title.Should().Be("Demo Unregistered");
        actual.Version.Should().Be("v1");
        actual.NoteId.Should().Be("note-7");
        actual.Detail.Should().Contain("note-7");
        new DemoUnregisteredProblem().NoteId.Should().BeEmpty();
    }

    [Fact]
    public void It_should_expose_the_wire_contract_helper_the_demo_composes_with()
    {
        // Act
        var actual = Encoding.UTF8.GetString(
            DemoDelivery.Envelope(DemoWebhookHandler.DemoProvider, "int-evt-8", DateTimeOffset.UtcNow, 1));

        // Assert
        actual.Should().Contain("\"version\":1").And.Contain("\"provider\":\"stripe\"");
        ServerEngineServiceCollectionExtensions.ShippedControllers.Should().HaveCount(3);
    }

    private static WebhookEnvelope Read(byte[] body) => WebhookEnvelopeReader.Read(body).Get();
}
