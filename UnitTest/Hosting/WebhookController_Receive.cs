using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.ServerEngine.TestHelper.Assertions;
using AtomiCloud.Diene.ServerEngine.TestHelper.Builders;
using AtomiCloud.Diene.ServerEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Hosting;

public class WebhookController_Receive
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task It_should_answer_exactly_200_when_a_handler_owns_the_event()
    {
        // Arrange
        var handler = new RecordingWebhookHandler();
        await using var host = await Host(handler);
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        var actual = await host.DeliverAsync("stripe", body, cancellationToken: Ct);

        // Assert
        actual.ShouldBeProcessed();
        handler.Received.Should().HaveCount(1);
    }

    [Fact]
    public async Task It_should_hand_the_handler_the_decoded_provider_payload()
    {
        // Arrange
        var handler = new RecordingWebhookHandler();
        await using var host = await Host(handler);
        var body = new WebhookEnvelopeBuilder(payload: """{"amount":"9.99"}""").ToBytes();

        // Act
        await host.DeliverAsync("stripe", body, cancellationToken: Ct);

        // Assert
        Encoding.UTF8.GetString(handler.Received[0].Payload.Body.Span).Should().Be("""{"amount":"9.99"}""");
    }

    [Fact]
    public async Task It_should_give_a_redelivery_the_same_idempotency_key()
    {
        // Arrange — mercury may redeliver, so the receiver must give a handler a stable key
        // rather than anything derived from the attempt.
        var handler = new RecordingWebhookHandler();
        await using var host = await Host(handler);
        var first = new WebhookEnvelopeBuilder().ToBytes();
        var retry = new WebhookEnvelopeBuilder()
            .WithNested("delivery", "attempt", JsonValue.Create(2))
            .ToBytes();

        // Act
        (await host.DeliverAsync("stripe", first, cancellationToken: Ct)).ShouldBeProcessed();
        (await host.DeliverAsync("stripe", retry, cancellationToken: Ct)).ShouldBeProcessed();

        // Assert
        handler.Keys.Should().HaveCount(2);
        handler.Keys[0].Should().Be(handler.Keys[1]);
    }

    [Fact]
    public async Task It_should_answer_exactly_421_when_the_handler_disowns_the_event()
    {
        // Arrange
        var handler = new RecordingWebhookHandler { Outcome = WebhookOutcome.NotMine };
        await using var host = await Host(handler);

        // Act
        var actual = await host.DeliverAsync("stripe", new WebhookEnvelopeBuilder().ToBytes(), cancellationToken: Ct);

        // Assert
        actual.ShouldBeNotMine();
    }

    [Fact]
    public async Task It_should_answer_421_rather_than_404_when_no_handler_is_registered()
    {
        // Arrange — 404 would be read as a real endpoint failure and retried for the full
        // 72-hour window, so it is never an ownership signal.
        await using var host = await Host();

        // Act
        var actual = await host.DeliverAsync("paypal", new WebhookEnvelopeBuilder("paypal").ToBytes(), cancellationToken: Ct);

        // Assert
        actual.ShouldBeNotMine();
        actual.StatusCode.Should().NotBe(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task It_should_answer_421_when_the_route_and_the_body_name_different_providers()
    {
        // Arrange — the compiled address was wrong for this event.
        var handler = new RecordingWebhookHandler();
        await using var host = await Host(handler);
        var body = new WebhookEnvelopeBuilder("paypal").ToBytes();

        // Act
        var actual = await host.DeliverAsync("stripe", body, cancellationToken: Ct);

        // Assert
        actual.ShouldBeNotMine();
        handler.Received.Should().BeEmpty();
    }

    [Fact]
    public async Task It_should_accept_a_route_segment_whose_casing_differs_from_the_body()
    {
        // Arrange
        var handler = new RecordingWebhookHandler();
        await using var host = await Host(handler);

        // Act
        var actual = await host.DeliverAsync("STRIPE", new WebhookEnvelopeBuilder().ToBytes(), cancellationToken: Ct);

        // Assert
        actual.ShouldBeProcessed();
    }

    [Theory]
    [ClassData(typeof(SignatureRefusalCases))]
    public async Task It_should_answer_401_and_never_421_for_a_signature_it_cannot_verify(
        string? header,
        string key)
    {
        // Arrange
        await using var host = await Host(new RecordingWebhookHandler());
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        var actual = await host.DeliverAsync("stripe", body, key: key, header: header, cancellationToken: Ct);

        // Assert
        actual.ShouldBeSignatureRejected();
        actual.StatusCode.Should().NotBe((HttpStatusCode)WebhookProtocol.NotMineStatus);
    }

    [Fact]
    public async Task It_should_answer_401_for_a_delivery_outside_the_freshness_window()
    {
        // Arrange
        await using var host = await Host(new RecordingWebhookHandler());
        var body = new WebhookEnvelopeBuilder().ToBytes();
        var stale = host.Clock.UtcNow.AddMinutes(-30);

        // Act
        var actual = await host.DeliverAsync("stripe", body, stale, cancellationToken: Ct);

        // Assert
        actual.ShouldBeSignatureRejected();
    }

    [Fact]
    public async Task It_should_answer_401_when_the_receiver_holds_no_signing_key()
    {
        // Arrange
        await using var host = await Host(new RecordingWebhookHandler());
        var body = new WebhookEnvelopeBuilder().ToBytes();
        host.Secrets.Forget();

        // Act
        var actual = await host.DeliverAsync("stripe", body, cancellationToken: Ct);

        // Assert
        actual.ShouldBeSignatureRejected();
    }

    [Fact]
    public async Task It_should_accept_a_delivery_signed_with_a_rotation_key_it_still_holds()
    {
        // Arrange
        await using var host = await Host(new RecordingWebhookHandler());
        host.Secrets.Rotate("incoming-key");
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        var actual = await host.DeliverAsync("stripe", body, key: "incoming-key", cancellationToken: Ct);

        // Assert
        actual.ShouldBeProcessed();
    }

    [Fact]
    public async Task It_should_refuse_a_signature_before_it_looks_at_the_media_type()
    {
        // Arrange — an unauthenticated caller must not learn what this receiver would accept.
        await using var host = await Host(new RecordingWebhookHandler());
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        var actual = await host.DeliverAsync("stripe", body, key: "wrong", mediaType: "text/plain", cancellationToken: Ct);

        // Assert
        actual.ShouldBeSignatureRejected();
    }

    [Fact]
    public async Task It_should_refuse_a_signature_before_it_parses_the_envelope()
    {
        // Arrange — no parser runs on unverified input.
        await using var host = await Host(new RecordingWebhookHandler());
        var body = Encoding.UTF8.GetBytes("not json at all");

        // Act
        var actual = await host.DeliverAsync("stripe", body, key: "wrong", cancellationToken: Ct);

        // Assert
        actual.ShouldBeSignatureRejected();
    }

    [Theory]
    [ClassData(typeof(WrongMediaTypeCases))]
    public async Task It_should_answer_415_for_a_media_type_that_is_not_the_delivery_envelope(
        string mediaType)
    {
        // Arrange
        await using var host = await Host(new RecordingWebhookHandler());
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        var actual = await host.DeliverAsync("stripe", body, mediaType: mediaType, cancellationToken: Ct);

        // Assert
        actual.ShouldBeUnsupportedMedia();
    }

    [Fact]
    public async Task It_should_accept_the_delivery_media_type_with_a_charset_parameter()
    {
        // Arrange — the contract names the media type, not the full header, so refusing a
        // charset would reject a signer for a reason the contract does not state.
        await using var host = await Host(new RecordingWebhookHandler());
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        var actual = await host.DeliverAsync(
            "stripe",
            body,
            mediaType: $"{WebhookProtocol.MediaType}; charset=utf-8",
            cancellationToken: Ct);

        // Assert
        actual.ShouldBeProcessed();
    }

    [Fact]
    public async Task It_should_answer_400_for_a_signed_but_malformed_envelope()
    {
        // Arrange
        var handler = new RecordingWebhookHandler();
        await using var host = await Host(handler);
        var body = new WebhookEnvelopeBuilder().With("tenantId", null).ToBytes();

        // Act
        var actual = await host.DeliverAsync("stripe", body, cancellationToken: Ct);

        // Assert
        actual.ShouldBeMalformedEnvelope();
        handler.Received.Should().BeEmpty();
    }

    [Fact]
    public async Task It_should_name_the_offending_field_in_the_malformed_envelope_problem()
    {
        // Arrange
        await using var host = await Host(new RecordingWebhookHandler());
        var body = new WebhookEnvelopeBuilder()
            .WithNested("delivery", "attempt", JsonValue.Create(0))
            .ToBytes();

        // Act
        var response = await host.DeliverAsync("stripe", body, cancellationToken: Ct);
        var actual = (await response.Should().BeRfc9457()).Which;

        // Assert
        actual.Detail.Should().Contain("delivery.attempt");
    }

    [Fact]
    public async Task It_should_render_a_handler_problem_through_the_shared_filter()
    {
        // Arrange — a typed problem from a handler is a REAL error, so mercury's retry decision
        // follows the consumer's own status policy rather than this package's.
        var handler = new RecordingWebhookHandler
        {
            Failure = new EntityConflict("Already processed differently.", typeof(WebhookController_Receive)),
        };
        await using var host = await Host(handler);

        // Act
        var actual = await host.DeliverAsync("stripe", new WebhookEnvelopeBuilder().ToBytes(), cancellationToken: Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.Conflict);
        await actual.Should().BeRfc9457();
    }

    [Fact]
    public async Task It_should_write_every_refusal_as_an_rfc_9457_envelope()
    {
        // Arrange
        await using var host = await Host(new RecordingWebhookHandler());
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        var rejected = await host.DeliverAsync("stripe", body, key: "wrong", cancellationToken: Ct);
        var unsupported = await host.DeliverAsync("stripe", body, mediaType: "application/json", cancellationToken: Ct);
        var notMine = await host.DeliverAsync("paypal", new WebhookEnvelopeBuilder("paypal").ToBytes(), cancellationToken: Ct);

        // Assert
        await rejected.Should().BeRfc9457();
        await unsupported.Should().BeRfc9457();
        await notMine.Should().BeRfc9457();
    }

    [Fact]
    public async Task It_should_verify_an_empty_body_before_reporting_it_as_malformed()
    {
        // Arrange
        await using var host = await Host(new RecordingWebhookHandler());

        // Act
        var actual = await host.DeliverAsync("stripe", [], cancellationToken: Ct);

        // Assert
        actual.ShouldBeMalformedEnvelope();
    }

    private static Task<ServerEngineTestHost> Host(params IWebhookHandler[] handlers) =>
        ServerEngineTestHost.StartAsync(options =>
        {
            foreach (var handler in handlers) options.Handlers.Add(handler);
        });

    private sealed class SignatureRefusalCases : TheoryData<string?, string>
    {
        public SignatureRefusalCases()
        {
            this.Add(null, "the-wrong-secret");
            this.Add(string.Empty, WebhookRequestSigner.DefaultKey);
            this.Add("t=1", WebhookRequestSigner.DefaultKey);
            this.Add("garbage", WebhookRequestSigner.DefaultKey);
            this.Add($"t=1, v1={new string('a', 64)}", WebhookRequestSigner.DefaultKey);
        }
    }

    private sealed class WrongMediaTypeCases : TheoryData<string>
    {
        public WrongMediaTypeCases()
        {
            this.Add("application/json");
            this.Add("text/plain");
            this.Add("application/vnd.atomi.webhook.v2+json");
        }
    }
}
