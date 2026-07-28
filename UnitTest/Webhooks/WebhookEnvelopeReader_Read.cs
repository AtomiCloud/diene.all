using System.Text;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.ServerEngine.TestHelper.Builders;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Webhooks;

public class WebhookEnvelopeReader_Read
{
    [Fact]
    public void It_should_read_every_field_a_receiver_may_rely_on()
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder(payload: """{"amount":"12.50"}""").ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body).Get();

        // Assert
        actual.Version.Should().Be(1);
        actual.EventId.Should().Be("evt-1");
        actual.DedupId.Should().Be("native:evt-1");
        actual.TenantId.Should().Be("tenant-1");
        actual.RouteId.Should().Be("route-1");
        actual.Provider.Should().Be("stripe");
        actual.LandingLandscape.Should().Be("lapras");
        actual.ReceivedAt.Should().Be(WebhookEnvelopeBuilder.DefaultReceivedAt);
        actual.ProviderEventId.Should().Be("provider-evt-1");
        actual.ProviderTimestamp.Should().Be(WebhookEnvelopeBuilder.DefaultReceivedAt);
        actual.ProviderSequence.Should().Be("1");
        actual.ProviderHeaders.Should().ContainKey("x-provider-event");
        actual.ProviderHeaders["x-provider-event"].Should().Equal("evt-1");
        actual.Payload.ContentType.Should().Be("application/json");
        Encoding.UTF8.GetString(actual.Payload.Body.Span).Should().Be("""{"amount":"12.50"}""");
        actual.Delivery.EndpointId.Should().Be("endpoint-1");
        actual.Delivery.Attempt.Should().Be(1);
        actual.Delivery.Replay.Should().BeFalse();
    }

    [Fact]
    public void It_should_ignore_a_field_it_does_not_know()
    {
        // Arrange — the contract requires unknown fields to be ignored while version is 1, so
        // mercury can add one without a synchronized release of every receiver.
        var body = new WebhookEnvelopeBuilder().With("somethingNew", JsonValue.Create("value")).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.IsSuccess().Should().BeTrue();
    }

    [Fact]
    public void It_should_accept_absent_optional_provider_metadata()
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder()
            .With("providerEventId", null)
            .With("providerTimestamp", JsonValue.Create((string?)null))
            .With("providerSequence", null)
            .ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body).Get();

        // Assert
        actual.ProviderEventId.Should().BeNull();
        actual.ProviderTimestamp.Should().BeNull();
        actual.ProviderSequence.Should().BeNull();
    }

    [Fact]
    public void It_should_accept_an_empty_provider_header_map()
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().With("providerHeaders", new JsonObject()).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body).Get();

        // Assert
        actual.ProviderHeaders.Should().BeEmpty();
    }

    [Fact]
    public void It_should_accept_a_replay_attempt_above_one()
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder()
            .WithNested("delivery", "attempt", JsonValue.Create(4))
            .WithNested("delivery", "replay", JsonValue.Create(true))
            .ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body).Get();

        // Assert
        actual.Delivery.Attempt.Should().Be(4);
        actual.Delivery.Replay.Should().BeTrue();
    }

    [Fact]
    public void It_should_accept_a_hashed_dedup_id()
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder()
            .With("dedupId", JsonValue.Create($"sha256:{new string('a', 64)}"))
            .ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.IsSuccess().Should().BeTrue();
    }

    [Theory]
    [ClassData(typeof(NonObjectBodyCases))]
    public void It_should_refuse_a_body_that_is_not_a_json_object(string raw, string reason)
    {
        // Act
        var actual = WebhookEnvelopeReader.Read(Encoding.UTF8.GetBytes(raw));

        // Assert
        actual.GetFailure().Field.Should().Be("$");
        actual.GetFailure().Reason.Should().Contain(reason);
    }

    [Theory]
    [ClassData(typeof(BadVersionCases))]
    public void It_should_refuse_an_envelope_version_it_does_not_implement(JsonNode? version, string reason)
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().With("version", version).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be("version");
        actual.GetFailure().Reason.Should().Contain(reason);
    }

    [Theory]
    [ClassData(typeof(RequiredStringCases))]
    public void It_should_refuse_a_blank_or_absent_required_string(string field, JsonNode? value, string reason)
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().With(field, value).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be(field);
        actual.GetFailure().Reason.Should().Contain(reason);
    }

    [Theory]
    [ClassData(typeof(BadProviderCases))]
    public void It_should_refuse_a_provider_that_is_not_a_lowercase_id(string provider)
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().With("provider", JsonValue.Create(provider)).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be("provider");
        actual.GetFailure().Reason.Should().Contain("lowercase provider id");
    }

    [Theory]
    [ClassData(typeof(BadDedupCases))]
    public void It_should_refuse_a_dedup_id_that_is_not_contract_shaped(string dedupId, string reason)
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().With("dedupId", JsonValue.Create(dedupId)).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be("dedupId");
        actual.GetFailure().Reason.Should().Contain(reason);
    }

    [Theory]
    [ClassData(typeof(BadInstantCases))]
    public void It_should_refuse_a_receive_instant_that_is_not_rfc_3339(JsonNode? value, string reason)
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().With("receivedAt", value).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be("receivedAt");
        actual.GetFailure().Reason.Should().Contain(reason);
    }

    [Theory]
    [ClassData(typeof(BadOptionalCases))]
    public void It_should_refuse_optional_provider_metadata_of_the_wrong_type(
        string field,
        JsonNode value,
        string reason)
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().With(field, value).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be(field);
        actual.GetFailure().Reason.Should().Contain(reason);
    }

    [Theory]
    [ClassData(typeof(BadHeaderMapCases))]
    public void It_should_refuse_a_provider_header_map_that_breaks_the_allowlist_shape(
        JsonNode? headers,
        string field,
        string reason)
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().With("providerHeaders", headers).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be(field);
        actual.GetFailure().Reason.Should().Contain(reason);
    }

    [Fact]
    public void It_should_refuse_a_payload_that_is_not_an_object()
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().With("payload", JsonValue.Create("nope")).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be("payload");
        actual.GetFailure().Reason.Should().Contain("must be an object");
    }

    [Theory]
    [ClassData(typeof(BadPayloadMemberCases))]
    public void It_should_refuse_a_payload_member_that_breaks_the_contract(
        string member,
        JsonNode? value,
        string field,
        string reason)
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().WithNested("payload", member, value).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be(field);
        actual.GetFailure().Reason.Should().Contain(reason);
    }

    [Fact]
    public void It_should_refuse_url_safe_base64_in_the_payload()
    {
        // Arrange — the contract fixes padded standard base64. Accepting both alphabets would
        // let one payload arrive under two encodings, only one of which the signature covered.
        var body = new WebhookEnvelopeBuilder()
            .WithNested("payload", "bodyBase64", JsonValue.Create("-_-_"))
            .ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be("payload.bodyBase64");
    }

    [Fact]
    public void It_should_refuse_a_delivery_block_that_is_not_an_object()
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().With("delivery", JsonValue.Create(7)).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be("delivery");
        actual.GetFailure().Reason.Should().Contain("must be an object");
    }

    [Theory]
    [ClassData(typeof(BadDeliveryMemberCases))]
    public void It_should_refuse_a_delivery_member_that_breaks_the_contract(
        string member,
        JsonNode? value,
        string field,
        string reason)
    {
        // Arrange
        var body = new WebhookEnvelopeBuilder().WithNested("delivery", member, value).ToBytes();

        // Act
        var actual = WebhookEnvelopeReader.Read(body);

        // Assert
        actual.GetFailure().Field.Should().Be(field);
        actual.GetFailure().Reason.Should().Contain(reason);
    }

    private sealed class NonObjectBodyCases : TheoryData<string, string>
    {
        public NonObjectBodyCases()
        {
            this.Add("not json at all", "not valid JSON");
            this.Add("{\"unterminated\":", "not valid JSON");
            this.Add("[1,2,3]", "must be a JSON object");
            this.Add("\"a string\"", "must be a JSON object");
        }
    }

    private sealed class BadVersionCases : TheoryData<JsonNode?, string>
    {
        public BadVersionCases()
        {
            this.Add(JsonValue.Create(2), "Only envelope version 1");
            this.Add(JsonValue.Create(0), "Only envelope version 1");
            this.Add(null, "must be an integer");
            this.Add(JsonValue.Create("1"), "must be an integer");
            this.Add(JsonValue.Create(1.5), "must be an integer");
        }
    }

    private sealed class RequiredStringCases : TheoryData<string, JsonNode?, string>
    {
        public RequiredStringCases()
        {
            this.Add("eventId", null, "must be a string");
            this.Add("eventId", JsonValue.Create(string.Empty), "must not be blank");
            this.Add("eventId", JsonValue.Create("   "), "must not be blank");
            this.Add("eventId", JsonValue.Create(7), "must be a string");
            this.Add("tenantId", null, "must be a string");
            this.Add("routeId", JsonValue.Create(" "), "must not be blank");
            this.Add("landingLandscape", null, "must be a string");
        }
    }

    private sealed class BadProviderCases : TheoryData<string>
    {
        public BadProviderCases()
        {
            this.Add("Stripe");
            this.Add("STRIPE");
            this.Add("-stripe");
            this.Add("stripe/live");
            this.Add("stripe live");
        }
    }

    private sealed class BadDedupCases : TheoryData<string, string>
    {
        public BadDedupCases()
        {
            this.Add("evt-1", "'native:' or 'sha256:' prefixed");
            this.Add("md5:abc", "'native:' or 'sha256:' prefixed");
            this.Add("native:", "unpadded base64url");
            this.Add("native:has padding=", "unpadded base64url");
            this.Add("native:has/slash", "unpadded base64url");
            this.Add($"sha256:{new string('a', 63)}", "64 lowercase hex");
            this.Add($"sha256:{new string('A', 64)}", "64 lowercase hex");
            this.Add($"sha256:{new string('g', 64)}", "64 lowercase hex");
        }
    }

    private sealed class BadInstantCases : TheoryData<JsonNode?, string>
    {
        public BadInstantCases()
        {
            this.Add(JsonValue.Create("2026-13-01T00:00:00Z"), "RFC 3339 instant");
            this.Add(JsonValue.Create("01-01-2026"), "RFC 3339 instant");
            this.Add(JsonValue.Create("not a date"), "RFC 3339 instant");
            this.Add(null, "must be a string");
        }
    }

    private sealed class BadOptionalCases : TheoryData<string, JsonNode, string>
    {
        public BadOptionalCases()
        {
            this.Add("providerEventId", JsonValue.Create(7), "string or null");
            this.Add("providerSequence", new JsonArray(1), "string or null");
            this.Add("providerTimestamp", JsonValue.Create("nope"), "RFC 3339 instant or null");
            this.Add("providerTimestamp", JsonValue.Create(7), "string or null");
        }
    }

    private sealed class BadHeaderMapCases : TheoryData<JsonNode?, string, string>
    {
        public BadHeaderMapCases()
        {
            this.Add(null, "providerHeaders", "must be an object");
            this.Add(JsonValue.Create("x=1"), "providerHeaders", "must be an object");
            this.Add(
                new JsonObject { ["X-Upper"] = new JsonArray("v") },
                "providerHeaders.X-Upper",
                "must be lowercase");
            this.Add(
                new JsonObject { ["x-scalar"] = JsonValue.Create("v") },
                "providerHeaders.x-scalar",
                "must be an array");
            this.Add(
                new JsonObject { ["x-mixed"] = new JsonArray(JsonValue.Create(1)) },
                "providerHeaders.x-mixed",
                "must be strings");
        }
    }

    private sealed class BadPayloadMemberCases : TheoryData<string, JsonNode?, string, string>
    {
        public BadPayloadMemberCases()
        {
            this.Add("contentType", null, "payload.contentType", "must be a string");
            this.Add("contentType", JsonValue.Create(" "), "payload.contentType", "must not be blank");
            this.Add("bodyBase64", null, "payload.bodyBase64", "must be a string");
            this.Add("bodyBase64", JsonValue.Create("not base64!!"), "payload.bodyBase64", "padded standard base64");

            // "YWJjZA" decodes to "abcd" only if the reader supplies the missing "==". A decoder
            // that pads for the sender accepts bytes no signature covered.
            this.Add("bodyBase64", JsonValue.Create("YWJjZA"), "payload.bodyBase64", "padded standard base64");
        }
    }

    private sealed class BadDeliveryMemberCases : TheoryData<string, JsonNode?, string, string>
    {
        public BadDeliveryMemberCases()
        {
            this.Add("endpointId", null, "delivery.endpointId", "must be a string");
            this.Add("endpointId", JsonValue.Create(""), "delivery.endpointId", "must not be blank");
            this.Add("attempt", null, "delivery.attempt", "must be an integer");
            this.Add("attempt", JsonValue.Create("1"), "delivery.attempt", "must be an integer");
            this.Add("attempt", JsonValue.Create(0), "delivery.attempt", "must start at 1");
            this.Add("attempt", JsonValue.Create(-3), "delivery.attempt", "must start at 1");
            this.Add("replay", null, "delivery.replay", "must be a boolean");
            this.Add("replay", JsonValue.Create("false"), "delivery.replay", "must be a boolean");
        }
    }
}

public class WebhookEnvelopeError_ToString
{
    [Fact]
    public void It_should_render_the_field_and_reason_on_one_line()
    {
        // Arrange
        var subject = new WebhookEnvelopeError("delivery.attempt", "Attempt must start at 1.");

        // Act
        var actual = subject.ToString();

        // Assert
        actual.Should().Be("delivery.attempt: Attempt must start at 1.");
    }
}
