using System.Text;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.CoreUtils;
using AtomiCloud.Diene.ServerEngine.Webhooks;

namespace AtomiCloud.Diene.ServerEngine.TestHelper.Builders;

/// <summary>
/// Builds C0 §11 version-1 delivery envelopes, valid by default and mutable field by field.
/// </summary>
/// <remarks>
/// The builder produces a <see cref="JsonObject" /> rather than a typed record, and that is the
/// point: the interesting tests are the INVALID ones — a missing field, a non-lowercase provider
/// header, an unpadded payload — and a typed record cannot express those. A consumer proving its
/// receiver rejects a malformed delivery needs to be able to build one.
/// </remarks>
public sealed class WebhookEnvelopeBuilder
{
    private readonly JsonObject _envelope;

    /// <summary>Creates a builder holding a fully valid envelope.</summary>
    public WebhookEnvelopeBuilder(
        string provider = "stripe",
        string eventId = "evt-1",
        DateTimeOffset? receivedAt = null,
        string payload = """{"ok":true}""")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(provider);
        ArgumentException.ThrowIfNullOrWhiteSpace(eventId);
        ArgumentNullException.ThrowIfNull(payload);

        var instant = Wire.Format(receivedAt ?? DefaultReceivedAt);
        this._envelope = new JsonObject
        {
            ["version"] = WebhookProtocol.EnvelopeVersion,
            ["eventId"] = eventId,
            ["dedupId"] = $"native:{eventId}",
            ["tenantId"] = "tenant-1",
            ["routeId"] = "route-1",
            ["provider"] = provider,
            ["landingLandscape"] = "lapras",
            ["receivedAt"] = instant,
            ["providerEventId"] = $"provider-{eventId}",
            ["providerTimestamp"] = instant,
            ["providerSequence"] = "1",
            ["providerHeaders"] = new JsonObject { ["x-provider-event"] = new JsonArray(eventId) },
            ["payload"] = new JsonObject
            {
                ["contentType"] = "application/json",
                ["bodyBase64"] = Convert.ToBase64String(Encoding.UTF8.GetBytes(payload)),
            },
            ["delivery"] = new JsonObject
            {
                ["endpointId"] = "endpoint-1",
                ["attempt"] = 1,
                ["replay"] = false,
            },
        };
    }

    /// <summary>The stable instant used when a test does not care which one.</summary>
    public static DateTimeOffset DefaultReceivedAt { get; } = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);

    /// <summary>Replaces a top-level member, or removes it when the value is null.</summary>
    public WebhookEnvelopeBuilder With(string name, JsonNode? value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);

        if (value is null)
        {
            this._envelope.Remove(name);
            return this;
        }

        this._envelope[name] = value;
        return this;
    }

    /// <summary>Replaces a member of a nested object such as <c>payload</c> or <c>delivery</c>.</summary>
    public WebhookEnvelopeBuilder WithNested(string parent, string name, JsonNode? value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(parent);
        ArgumentException.ThrowIfNullOrWhiteSpace(name);

        if (this._envelope[parent] is not JsonObject nested)
        {
            throw new InvalidOperationException($"Envelope member '{parent}' is not an object.");
        }

        if (value is null)
        {
            nested.Remove(name);
            return this;
        }

        nested[name] = value;
        return this;
    }

    /// <summary>Renders the envelope as the exact UTF-8 bytes a delivery carries.</summary>
    public byte[] ToBytes() => Encoding.UTF8.GetBytes(this._envelope.ToJsonString());

    /// <summary>Renders the envelope as JSON text.</summary>
    public override string ToString() => this._envelope.ToJsonString();
}
