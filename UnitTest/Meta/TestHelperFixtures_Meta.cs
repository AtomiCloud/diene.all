using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.ServerEngine.TestHelper.Builders;
using AtomiCloud.Diene.ServerEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Meta;

/// <summary>
/// Invariants for the shipped builders and fakes.
/// </summary>
/// <remarks>
/// A fixture's defect is invisible in the suite that uses it: a builder that quietly produced an
/// invalid envelope would make every consumer's rejection test pass for the wrong reason. These
/// pin what the fixtures actually produce.
/// </remarks>
public class WebhookEnvelopeBuilder_Meta
{
    [Fact]
    public void It_should_produce_an_envelope_the_shipped_reader_accepts()
    {
        // Arrange — the invariant that matters: the default fixture is VALID. If it were not,
        // every "rejects a malformed envelope" test would pass without testing its own case.
        var subject = new WebhookEnvelopeBuilder();

        // Act
        var actual = WebhookEnvelopeReader.Read(subject.ToBytes());

        // Assert
        actual.IsSuccess().Should().BeTrue();
    }

    [Fact]
    public void It_should_carry_the_payload_it_was_given()
    {
        // Arrange
        var subject = new WebhookEnvelopeBuilder(payload: """{"amount":"1.00"}""");

        // Act
        var actual = WebhookEnvelopeReader.Read(subject.ToBytes()).Get();

        // Assert
        Encoding.UTF8.GetString(actual.Payload.Body.Span).Should().Be("""{"amount":"1.00"}""");
    }

    [Fact]
    public void It_should_name_the_provider_and_event_it_was_given()
    {
        // Arrange
        var subject = new WebhookEnvelopeBuilder("paypal", "evt-9");

        // Act
        var actual = WebhookEnvelopeReader.Read(subject.ToBytes()).Get();

        // Assert
        actual.Provider.Should().Be("paypal");
        actual.EventId.Should().Be("evt-9");
        actual.DedupId.Should().Be("native:evt-9");
    }

    [Fact]
    public void It_should_use_the_receive_instant_it_was_given()
    {
        // Arrange
        var instant = new DateTimeOffset(2026, 6, 7, 8, 9, 10, TimeSpan.Zero);
        var subject = new WebhookEnvelopeBuilder(receivedAt: instant);

        // Act
        var actual = WebhookEnvelopeReader.Read(subject.ToBytes()).Get();

        // Assert
        actual.ReceivedAt.Should().Be(instant);
    }

    [Fact]
    public void It_should_replace_a_top_level_member()
    {
        // Arrange
        var subject = new WebhookEnvelopeBuilder().With("tenantId", JsonValue.Create("tenant-9"));

        // Act
        var actual = WebhookEnvelopeReader.Read(subject.ToBytes()).Get();

        // Assert
        actual.TenantId.Should().Be("tenant-9");
    }

    [Fact]
    public void It_should_remove_a_top_level_member_when_given_null()
    {
        // Arrange — removing is how a consumer builds the absent-field case; writing JSON null
        // instead would exercise a different branch of the reader.
        var subject = new WebhookEnvelopeBuilder().With("tenantId", null);

        // Act
        var actual = JsonNode.Parse(subject.ToString())!.AsObject();

        // Assert
        actual.ContainsKey("tenantId").Should().BeFalse();
    }

    [Fact]
    public void It_should_replace_a_nested_member()
    {
        // Arrange
        var subject = new WebhookEnvelopeBuilder().WithNested("delivery", "attempt", JsonValue.Create(3));

        // Act
        var actual = WebhookEnvelopeReader.Read(subject.ToBytes()).Get();

        // Assert
        actual.Delivery.Attempt.Should().Be(3);
    }

    [Fact]
    public void It_should_remove_a_nested_member_when_given_null()
    {
        // Arrange
        var subject = new WebhookEnvelopeBuilder().WithNested("payload", "contentType", null);

        // Act
        var actual = JsonNode.Parse(subject.ToString())!.AsObject()["payload"]!.AsObject();

        // Assert
        actual.ContainsKey("contentType").Should().BeFalse();
    }

    [Fact]
    public void It_should_refuse_to_reach_into_a_member_that_is_not_an_object()
    {
        // Arrange — failing loudly beats writing into a member that does not exist, which would
        // silently produce an envelope the test did not intend.
        var subject = new WebhookEnvelopeBuilder();

        // Act
        var act = () => subject.WithNested("eventId", "nope", JsonValue.Create(1));

        // Assert
        act.Should().Throw<InvalidOperationException>().WithMessage("*'eventId' is not an object*");
    }

    [Theory]
    [ClassData(typeof(BlankArgumentCases))]
    public void It_should_refuse_a_blank_construction_argument(string? provider, string? eventId)
    {
        // Act
        var act = () => new WebhookEnvelopeBuilder(provider!, eventId!);

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_refuse_a_null_payload()
    {
        // Act
        var act = () => new WebhookEnvelopeBuilder(payload: null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Theory]
    [ClassData(typeof(BlankMemberNameCases))]
    public void It_should_refuse_a_blank_member_name(string? name)
    {
        // Arrange
        var subject = new WebhookEnvelopeBuilder();

        // Act
        var top = () => subject.With(name!, JsonValue.Create(1));
        var nested = () => subject.WithNested("payload", name!, JsonValue.Create(1));
        var parent = () => subject.WithNested(name!, "contentType", JsonValue.Create(1));

        // Assert
        top.Should().Throw<ArgumentException>();
        nested.Should().Throw<ArgumentException>();
        parent.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_render_the_same_json_as_text_and_bytes()
    {
        // Arrange
        var subject = new WebhookEnvelopeBuilder();

        // Act
        var text = subject.ToString();
        var bytes = subject.ToBytes();

        // Assert
        Encoding.UTF8.GetString(bytes).Should().Be(text);
    }

    private sealed class BlankArgumentCases : TheoryData<string?, string?>
    {
        public BlankArgumentCases()
        {
            this.Add(null!, "evt-1");
            this.Add(string.Empty, "evt-1");
            this.Add("stripe", null!);
            this.Add("stripe", "   ");
        }
    }

    private sealed class BlankMemberNameCases : TheoryData<string?>
    {
        public BlankMemberNameCases()
        {
            this.Add(null!);
            this.Add(string.Empty);
            this.Add("  ");
        }
    }
}

public class WebhookRequestSigner_Meta
{
    private static readonly DateTimeOffset Now = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);

    [Fact]
    public void It_should_produce_a_header_the_shipped_parser_accepts()
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        var actual = WebhookRequestSigner.Header(Now, body);

        // Assert
        actual.Should().MatchRegex("^t=[0-9]+, v1=[0-9a-f]{64}$");
    }

    [Fact]
    public void It_should_produce_a_digest_that_changes_with_the_body()
    {
        // Arrange
        var first = Encoding.UTF8.GetBytes("a");
        var second = Encoding.UTF8.GetBytes("b");

        // Act
        var left = WebhookRequestSigner.Digest(1, first);
        var right = WebhookRequestSigner.Digest(1, second);

        // Assert
        left.Should().NotBe(right);
    }

    [Fact]
    public void It_should_produce_a_digest_that_changes_with_the_timestamp()
    {
        // Arrange — the timestamp is inside the signed payload, which is what stops a captured
        // digest from being replayed under a fresh t.
        var body = Encoding.UTF8.GetBytes("a");

        // Act
        var left = WebhookRequestSigner.Digest(1, body);
        var right = WebhookRequestSigner.Digest(2, body);

        // Assert
        left.Should().NotBe(right);
    }

    [Fact]
    public void It_should_produce_a_digest_that_changes_with_the_key()
    {
        // Arrange
        var body = Encoding.UTF8.GetBytes("a");

        // Act
        var left = WebhookRequestSigner.Digest(1, body, "one");
        var right = WebhookRequestSigner.Digest(1, body, "two");

        // Assert
        left.Should().NotBe(right);
    }

    [Fact]
    public void It_should_build_a_request_carrying_the_route_media_type_and_signature()
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        using var actual = WebhookRequestSigner.Request("stripe", body, Now);

        // Assert
        actual.Method.Should().Be(HttpMethod.Post);
        actual.RequestUri!.ToString().Should().Be($"/{WebhookProtocol.RoutePrefix}/stripe");
        actual.Content!.Headers.ContentType!.MediaType.Should().Be(WebhookProtocol.MediaType);
        actual.Headers.GetValues(WebhookProtocol.SignatureHeader).Should().ContainSingle();
    }

    [Fact]
    public void It_should_carry_a_deliberately_malformed_header_through_unvalidated()
    {
        // Arrange — a test that supplies a broken header must reach the receiver's parser; the
        // client's own header validation would otherwise reject it first and the check under
        // test would never run.
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        using var actual = WebhookRequestSigner.Request("stripe", body, Now, header: "t=1, v1=nope, extra");

        // Assert
        actual.Headers.GetValues(WebhookProtocol.SignatureHeader).Should().Equal(["t=1, v1=nope, extra"]);
    }

    [Fact]
    public void It_should_accept_a_media_type_carrying_parameters()
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        using var actual = WebhookRequestSigner.Request(
            "stripe",
            body,
            Now,
            mediaType: $"{WebhookProtocol.MediaType}; charset=utf-8");

        // Assert
        actual.Content!.Headers.ContentType!.CharSet.Should().Be("utf-8");
    }

    [Theory]
    [ClassData(typeof(BlankCases))]
    public void It_should_refuse_a_blank_provider_or_key(string? value)
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().ToBytes();

        // Act
        var provider = () => WebhookRequestSigner.Request(value!, body, Now);
        var header = () => WebhookRequestSigner.Header(Now, body, value!);
        var digest = () => WebhookRequestSigner.Digest(1, body, value!);

        // Assert
        provider.Should().Throw<ArgumentException>();
        header.Should().Throw<ArgumentException>();
        digest.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_refuse_a_null_body()
    {
        // Act
        var act = () => WebhookRequestSigner.Request("stripe", null!, Now);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    private sealed class BlankCases : TheoryData<string?>
    {
        public BlankCases()
        {
            this.Add(null!);
            this.Add(string.Empty);
            this.Add("   ");
        }
    }
}

public class FakeWebhookSecretProvider_Meta
{
    [Fact]
    public void It_should_hold_the_keys_it_was_given()
    {
        // Act
        var actual = new FakeWebhookSecretProvider("one", "two");

        // Assert
        actual.SigningKeys.Should().Equal(["one", "two"]);
    }

    [Fact]
    public void It_should_permit_an_empty_key_set_the_shipped_provider_refuses()
    {
        // Arrange — a receiver whose secret failed to materialize is a real production state, so
        // a test must be able to reach it. The shipped provider refuses it at construction.
        var actual = new FakeWebhookSecretProvider();

        // Act
        var shipped = () => new StaticWebhookSecretProvider();

        // Assert
        actual.SigningKeys.Should().BeEmpty();
        shipped.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_add_an_incoming_key_while_the_outgoing_one_stays_live()
    {
        // Arrange
        var subject = new FakeWebhookSecretProvider("outgoing");

        // Act
        var actual = subject.Rotate("incoming");

        // Assert
        actual.Should().BeSameAs(subject);
        subject.SigningKeys.Should().Equal(["outgoing", "incoming"]);
    }

    [Fact]
    public void It_should_drop_every_key_when_told_to_forget()
    {
        // Arrange
        var subject = new FakeWebhookSecretProvider("one", "two");

        // Act
        var actual = subject.Forget();

        // Assert
        actual.Should().BeSameAs(subject);
        subject.SigningKeys.Should().BeEmpty();
    }

    [Theory]
    [ClassData(typeof(BlankKeyCases))]
    public void It_should_refuse_rotating_in_a_blank_key(string? key)
    {
        // Arrange
        var subject = new FakeWebhookSecretProvider("one");

        // Act
        var act = () => subject.Rotate(key!);

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_refuse_a_null_key_array()
    {
        // Act
        var act = () => new FakeWebhookSecretProvider(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    private sealed class BlankKeyCases : TheoryData<string?>
    {
        public BlankKeyCases()
        {
            this.Add(null!);
            this.Add(string.Empty);
            this.Add("  ");
        }
    }
}

public class RecordingWebhookHandler_Meta
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task It_should_record_every_envelope_in_arrival_order()
    {
        // Arrange
        var subject = new RecordingWebhookHandler();
        var first = Envelope("evt-1");
        var second = Envelope("evt-2");

        // Act
        await subject.HandleAsync(first, Ct);
        await subject.HandleAsync(second, Ct);

        // Assert
        subject.Received.Should().HaveCount(2);
        subject.Received[0].EventId.Should().Be("evt-1");
        subject.Received[1].EventId.Should().Be("evt-2");
    }

    [Fact]
    public async Task It_should_expose_the_idempotency_key_of_every_delivery()
    {
        // Arrange
        var subject = new RecordingWebhookHandler();
        var envelope = Envelope("evt-1");

        // Act
        await subject.HandleAsync(envelope, Ct);

        // Assert
        subject.Keys.Should().Equal([WebhookIdempotency.KeyOf(envelope)]);
    }

    [Fact]
    public async Task It_should_answer_processed_by_default()
    {
        // Arrange
        var subject = new RecordingWebhookHandler();

        // Act
        var actual = await subject.HandleAsync(Envelope("evt-1"), Ct);

        // Assert
        actual.Get().Should().Be(WebhookOutcome.Processed);
    }

    [Fact]
    public async Task It_should_answer_the_outcome_it_was_set_to()
    {
        // Arrange
        var subject = new RecordingWebhookHandler { Outcome = WebhookOutcome.NotMine };

        // Act
        var actual = await subject.HandleAsync(Envelope("evt-1"), Ct);

        // Assert
        actual.Get().Should().Be(WebhookOutcome.NotMine);
    }

    [Fact]
    public async Task It_should_prefer_a_configured_failure_over_an_outcome()
    {
        // Arrange
        var problem = new EntityConflict("Conflict.", typeof(RecordingWebhookHandler_Meta));
        var subject = new RecordingWebhookHandler { Outcome = WebhookOutcome.Processed, Failure = problem };

        // Act
        var actual = await subject.HandleAsync(Envelope("evt-1"), Ct);

        // Assert
        actual.GetFailure().Should().BeSameAs(problem);
    }

    [Fact]
    public void It_should_serve_the_provider_it_was_created_for()
    {
        // Act
        var actual = new RecordingWebhookHandler("paypal");

        // Assert
        actual.Provider.Should().Be("paypal");
    }

    [Theory]
    [ClassData(typeof(BlankProviderCases))]
    public void It_should_refuse_a_blank_provider(string? provider)
    {
        // Act
        var act = () => new RecordingWebhookHandler(provider!);

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public async Task It_should_refuse_a_null_envelope()
    {
        // Arrange
        var subject = new RecordingWebhookHandler();

        // Act
        var act = async () => await subject.HandleAsync(null!, Ct);

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task It_should_observe_a_cancelled_token()
    {
        // Arrange
        var subject = new RecordingWebhookHandler();
        using var source = new CancellationTokenSource();
        await source.CancelAsync();

        // Act
        var act = async () => await subject.HandleAsync(Envelope("evt-1"), source.Token);

        // Assert
        await act.Should().ThrowAsync<OperationCanceledException>();
    }

    internal static WebhookEnvelope Envelope(string eventId) =>
        WebhookEnvelopeReader.Read(new WebhookEnvelopeBuilder(eventId: eventId).ToBytes()).Get();

    private sealed class BlankProviderCases : TheoryData<string?>
    {
        public BlankProviderCases()
        {
            this.Add(null!);
            this.Add(string.Empty);
            this.Add("  ");
        }
    }
}

public class ProbeUnregisteredProblem_Meta
{
    [Fact]
    public void It_should_describe_itself_as_a_versioned_problem_no_catalog_holds()
    {
        // Act
        var actual = new ProbeUnregisteredProblem();

        // Assert
        actual.Id.Should().Be("probe_unregistered");
        actual.Title.Should().Be("Probe Unregistered");
        actual.Version.Should().Be("v1");
        actual.Detail.Should().Contain("never registered");
    }

    [Fact]
    public void It_should_serialize_no_members_because_all_of_them_are_metadata()
    {
        // Arrange — Id, Title, Detail, and Version are JsonIgnored on every Diene problem, so
        // the data extension of a problem with no payload is an empty object.
        var subject = new ProbeUnregisteredProblem();

        // Act
        var actual = JsonSerializer.Serialize(subject);

        // Assert
        actual.Should().Be("{}");
    }
}
