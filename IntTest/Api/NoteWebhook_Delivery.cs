using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.ServerEngine.TestHelper.Assertions;
using AtomiCloud.Diene.ServerEngine.TestHelper.Builders;
using AtomiCloud.Diene.ServerEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;
using AtomiCloud.Diene.StandardConfig.Presets;
using AtomiCloud.Diene.StandardConfig.TestHelper.Containers;
using AtomiCloud.DotnetBase.App.StartUp.Registration;
using AtomiCloud.DotnetBase.App.Webhooks;
using FluentAssertions;
using StackExchange.Redis;

namespace AtomiCloud.DotnetBase.IntTest.Api;

/// <summary>
/// The inbound webhook contract, driven through the shipped receiver against the REAL
/// <see cref="NoteWebhookHandler"/> and a real cache.
/// </summary>
/// <remarks>
/// Status codes are asserted with the published helpers rather than by comparing numbers, because
/// the wrong-but-plausible answers are the whole hazard: 404 for an event this service does not own
/// would make mercury retry for its full 72-hour window and then dead-letter it, and any 2xx other
/// than 200 reads as a failure. The helpers refuse those by construction.
/// </remarks>
public class NoteWebhook_Delivery : IAsyncLifetime
{
    private StartedPreset<CacheBlock, CacheOption>? _cache;
    private IConnectionMultiplexer _connection = null!;

    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    public async ValueTask InitializeAsync()
    {
        this._cache = await StandardConfigContainers
            .StartCacheAsync(new StartRedisOptions { Key = "MAIN" }, Ct)
            .ConfigureAwait(false);

        // Built through the production helper, so the test connects the way the service does.
        var configuration = DomainRegistration.RedisConfiguration(this._cache.Block.Named(this._cache.Key));
        this._connection = await ConnectionMultiplexer.ConnectAsync(configuration).ConfigureAwait(false);
    }

    public async ValueTask DisposeAsync()
    {
        if (this._connection is not null) await this._connection.DisposeAsync();
        if (this._cache is not null) await this._cache.DisposeAsync();
    }

    [Fact]
    public async Task It_should_process_an_owned_event()
    {
        // Arrange
        await using var host = await this.StartAsync();
        var body = new WebhookEnvelopeBuilder(provider: NoteWebhookHandler.ProviderName).ToBytes();

        // Act
        var response = await host.DeliverAsync(NoteWebhookHandler.ProviderName, body, cancellationToken: Ct);

        // Assert — exactly 200. ShouldBeProcessed refuses every other 2xx.
        response.ShouldBeProcessed();
    }

    [Fact]
    public async Task It_should_record_exactly_one_side_effect_for_a_replayed_delivery()
    {
        // Arrange — the SAME envelope twice is what mercury does after acking the provider early.
        await using var host = await this.StartAsync();
        var body = new WebhookEnvelopeBuilder(provider: NoteWebhookHandler.ProviderName).ToBytes();

        // Act
        var first = await host.DeliverAsync(NoteWebhookHandler.ProviderName, body, cancellationToken: Ct);
        var second = await host.DeliverAsync(NoteWebhookHandler.ProviderName, body, cancellationToken: Ct);

        // Assert — a replay still answers 200; idempotent means the EFFECT happened once, not that
        // the second call was rejected.
        first.ShouldBeProcessed();
        second.ShouldBeProcessed();

        var effects = await this._connection.GetDatabase().SetLengthAsync(NoteWebhookHandler.EffectKey);
        effects.Should().Be(1, "a replay must not duplicate the side effect");
    }

    [Fact]
    public async Task It_should_record_two_side_effects_for_two_distinct_events()
    {
        // Arrange — proves the dedup key discriminates rather than swallowing everything.
        await using var host = await this.StartAsync();

        // Act
        var one = await host.DeliverAsync(
            NoteWebhookHandler.ProviderName,
            new WebhookEnvelopeBuilder(provider: NoteWebhookHandler.ProviderName, eventId: "evt-one").ToBytes(),
            cancellationToken: Ct);
        var two = await host.DeliverAsync(
            NoteWebhookHandler.ProviderName,
            new WebhookEnvelopeBuilder(provider: NoteWebhookHandler.ProviderName, eventId: "evt-two").ToBytes(),
            cancellationToken: Ct);

        // Assert
        one.ShouldBeProcessed();
        two.ShouldBeProcessed();
        var effects = await this._connection.GetDatabase().SetLengthAsync(NoteWebhookHandler.EffectKey);
        effects.Should().Be(2);
    }

    [Fact]
    public async Task It_should_answer_not_mine_for_a_provider_this_service_does_not_own()
    {
        // Arrange
        await using var host = await this.StartAsync();
        var body = new WebhookEnvelopeBuilder(provider: "someone-else").ToBytes();

        // Act
        var response = await host.DeliverAsync("someone-else", body, cancellationToken: Ct);

        // Assert — 421, NEVER 404. ShouldBeNotMine says so if the status is 404.
        response.ShouldBeNotMine();
    }

    [Fact]
    public async Task It_should_answer_a_real_handler_error_as_a_problem_rather_than_200_or_421()
    {
        // Arrange — NoteWebhookHandler never fails, so the ERROR tier is reached with a recording
        // handler set to fail. This asserts the ENGINE's mapping of a typed problem, which is the
        // tier under test; the owned-event and replay cases above use the real handler.
        var failing = new RecordingWebhookHandler("failing")
        {
            Failure = new EntityNotFound("the referenced note is gone", typeof(object), "missing"),
        };
        await using var host = await ServerEngineTestHost.StartAsync(options =>
        {
            options.Handlers.Add(failing);
            options.SigningKeys.Add(WebhookRequestSigner.DefaultKey);
        });

        // Act
        var response = await host.DeliverAsync(
            "failing",
            new WebhookEnvelopeBuilder(provider: "failing").ToBytes(),
            cancellationToken: Ct);

        // Assert — a real error is neither Processed nor NotMine, and it still leaves as RFC 9457
        // so mercury sees ONE contract for every failure.
        ((int)response.StatusCode).Should().NotBe(200);
        ((int)response.StatusCode).Should().NotBe(421);
        (await response.Should().BeRfc9457()).Which.Status.Should().Be((int)response.StatusCode);
    }

    private Task<ServerEngineTestHost> StartAsync() => ServerEngineTestHost.StartAsync(options =>
    {
        options.Handlers.Add(new NoteWebhookHandler(this._connection));
        options.SigningKeys.Add(WebhookRequestSigner.DefaultKey);
    });
}
