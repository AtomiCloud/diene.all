using System.Text.Json;
using System.Text.RegularExpressions;
using AtomiCloud.Diene.CoreUtils;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>
/// Reads a C0 §11 version-1 delivery envelope from raw request bytes.
/// </summary>
/// <remarks>
/// <para>
/// Every required field is checked and every failure is named. A receiver that accepted a
/// partially-formed envelope would hand a handler a record with an empty tenant id, and the
/// handler's idempotency key would then collide across tenants — a data-corruption bug whose
/// cause is three layers away from where it shows up.
/// </para>
/// <para>
/// Unknown fields are ignored, as the contract requires. Ignoring them is what lets mercury
/// add a field without a synchronized release of every receiver.
/// </para>
/// </remarks>
public static class WebhookEnvelopeReader
{
    private const int DedupSha256HexLength = 64;

    // Plain Regex fields rather than [GeneratedRegex]: the generator emits matcher branches this
    // library never reaches, and they would land in the shipped assembly's coverage ledger. A
    // source generator should not be able to lower the measured coverage of hand-written code.
    private static readonly Regex ProviderPattern = new("^[a-z0-9][a-z0-9._-]*$", RegexOptions.CultureInvariant);
    private static readonly Regex Base64UrlPattern = new("^[A-Za-z0-9_-]+$", RegexOptions.CultureInvariant);
    private static readonly Regex LowerHexPattern = new("^[0-9a-f]+$", RegexOptions.CultureInvariant);

    /// <summary>Parses and validates the envelope, returning the first field that failed.</summary>
    public static Result<WebhookEnvelope, WebhookEnvelopeError> Read(ReadOnlySpan<byte> body)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(body.ToArray());
        }
        catch (JsonException exception)
        {
            return new WebhookEnvelopeError("$", $"Body is not valid JSON: {exception.Message}");
        }

        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return new WebhookEnvelopeError("$", "Body must be a JSON object.");
            }

            return ReadObject(root);
        }
    }

    private static Result<WebhookEnvelope, WebhookEnvelopeError> ReadObject(JsonElement root)
    {
        var version = Integer(root, "version");
        if (version.IsFailure(out var versionError)) return versionError;
        if (version.Get() != WebhookProtocol.EnvelopeVersion)
        {
            return new WebhookEnvelopeError(
                "version",
                $"Only envelope version {WebhookProtocol.EnvelopeVersion} is supported.");
        }

        var strings = new[] { "eventId", "dedupId", "tenantId", "routeId", "provider", "landingLandscape" };
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var field in strings)
        {
            var value = RequiredString(root, field);
            if (value.IsFailure(out var stringError)) return stringError;
            values[field] = value.Get();
        }

        if (!ProviderPattern.IsMatch(values["provider"]))
        {
            return new WebhookEnvelopeError("provider", "Provider must be a lowercase provider id.");
        }

        var dedup = ValidateDedupId(values["dedupId"]);
        if (dedup.IsFailure(out var dedupError)) return dedupError;

        var receivedAt = Instant(root, "receivedAt");
        if (receivedAt.IsFailure(out var receivedError)) return receivedError;

        var providerEventId = OptionalString(root, "providerEventId");
        if (providerEventId.IsFailure(out var eventIdError)) return eventIdError;

        var providerSequence = OptionalString(root, "providerSequence");
        if (providerSequence.IsFailure(out var sequenceError)) return sequenceError;

        var providerTimestamp = OptionalInstant(root, "providerTimestamp");
        if (providerTimestamp.IsFailure(out var timestampError)) return timestampError;

        var headers = ReadProviderHeaders(root);
        if (headers.IsFailure(out var headerError)) return headerError;

        var payload = ReadPayload(root);
        if (payload.IsFailure(out var payloadError)) return payloadError;

        var delivery = ReadDelivery(root);
        if (delivery.IsFailure(out var deliveryError)) return deliveryError;

        return new WebhookEnvelope(
            version.Get(),
            values["eventId"],
            values["dedupId"],
            values["tenantId"],
            values["routeId"],
            values["provider"],
            values["landingLandscape"],
            receivedAt.Get(),
            providerEventId.Get(),
            providerTimestamp.Get(),
            providerSequence.Get(),
            headers.Get(),
            payload.Get(),
            delivery.Get());
    }

    private static Result<Unit, WebhookEnvelopeError> ValidateDedupId(string value)
    {
        const string nativePrefix = "native:";
        const string hashPrefix = "sha256:";

        if (value.StartsWith(nativePrefix, StringComparison.Ordinal))
        {
            return value.Length > nativePrefix.Length && Base64UrlPattern.IsMatch(value[nativePrefix.Length..])
                ? Result.Ok<Unit, WebhookEnvelopeError>(default)
                : new WebhookEnvelopeError("dedupId", "A native dedup id must carry unpadded base64url content.");
        }

        if (!value.StartsWith(hashPrefix, StringComparison.Ordinal))
        {
            return new WebhookEnvelopeError("dedupId", "Dedup id must be 'native:' or 'sha256:' prefixed.");
        }

        var hex = value[hashPrefix.Length..];
        return hex.Length == DedupSha256HexLength && LowerHexPattern.IsMatch(hex)
            ? Result.Ok<Unit, WebhookEnvelopeError>(default)
            : new WebhookEnvelopeError(
                "dedupId",
                $"A hashed dedup id must carry {DedupSha256HexLength} lowercase hex characters.");
    }

    private static Result<IReadOnlyDictionary<string, IReadOnlyList<string>>, WebhookEnvelopeError>
        ReadProviderHeaders(JsonElement root)
    {
        if (!root.TryGetProperty("providerHeaders", out var element) ||
            element.ValueKind != JsonValueKind.Object)
        {
            return new WebhookEnvelopeError("providerHeaders", "Provider headers must be an object.");
        }

        var headers = new Dictionary<string, IReadOnlyList<string>>(StringComparer.Ordinal);
        foreach (var property in element.EnumerateObject())
        {
            if (property.Name != property.Name.ToLowerInvariant())
            {
                return new WebhookEnvelopeError(
                    $"providerHeaders.{property.Name}",
                    "Provider header names must be lowercase.");
            }

            if (property.Value.ValueKind != JsonValueKind.Array)
            {
                return new WebhookEnvelopeError(
                    $"providerHeaders.{property.Name}",
                    "Provider header values must be an array.");
            }

            var values = new List<string>();
            foreach (var item in property.Value.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.String)
                {
                    return new WebhookEnvelopeError(
                        $"providerHeaders.{property.Name}",
                        "Provider header values must be strings.");
                }

                values.Add(item.GetString()!);
            }

            headers[property.Name] = values;
        }

        return headers;
    }

    private static Result<WebhookPayload, WebhookEnvelopeError> ReadPayload(JsonElement root)
    {
        if (!root.TryGetProperty("payload", out var element) || element.ValueKind != JsonValueKind.Object)
        {
            return new WebhookEnvelopeError("payload", "Payload must be an object.");
        }

        var contentType = RequiredString(element, "contentType", "payload.contentType");
        if (contentType.IsFailure(out var contentTypeError)) return contentTypeError;

        var encoded = RequiredString(element, "bodyBase64", "payload.bodyBase64");
        if (encoded.IsFailure(out var encodedError)) return encodedError;

        // Standard base64 WITH padding, per the contract. The URL-safe alphabet is
        // deliberately not accepted: admitting both spellings would let one payload arrive
        // under two encodings, and only one of them would match the signature that covered it.
        try
        {
            return new WebhookPayload(contentType.Get(), Convert.FromBase64String(encoded.Get()));
        }
        catch (FormatException)
        {
            return new WebhookEnvelopeError("payload.bodyBase64", "Payload body must be padded standard base64.");
        }
    }

    private static Result<WebhookDelivery, WebhookEnvelopeError> ReadDelivery(JsonElement root)
    {
        if (!root.TryGetProperty("delivery", out var element) || element.ValueKind != JsonValueKind.Object)
        {
            return new WebhookEnvelopeError("delivery", "Delivery must be an object.");
        }

        var endpointId = RequiredString(element, "endpointId", "delivery.endpointId");
        if (endpointId.IsFailure(out var endpointError)) return endpointError;

        var attempt = Integer(element, "attempt", "delivery.attempt");
        if (attempt.IsFailure(out var attemptError)) return attemptError;
        if (attempt.Get() < 1)
        {
            return new WebhookEnvelopeError("delivery.attempt", "Attempt must start at 1.");
        }

        if (!element.TryGetProperty("replay", out var replay) ||
            replay.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
        {
            return new WebhookEnvelopeError("delivery.replay", "Replay must be a boolean.");
        }

        return new WebhookDelivery(endpointId.Get(), attempt.Get(), replay.GetBoolean());
    }

    private static Result<string, WebhookEnvelopeError> RequiredString(
        JsonElement root,
        string name,
        string? path = null)
    {
        var field = path ?? name;
        if (!root.TryGetProperty(name, out var element) || element.ValueKind != JsonValueKind.String)
        {
            return new WebhookEnvelopeError(field, "Value must be a string.");
        }

        var value = element.GetString();
        return string.IsNullOrWhiteSpace(value)
            ? new WebhookEnvelopeError(field, "Value must not be blank.")
            : value;
    }

    private static Result<string?, WebhookEnvelopeError> OptionalString(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var element) || element.ValueKind == JsonValueKind.Null)
        {
            return Result.Ok<string?, WebhookEnvelopeError>(null);
        }

        return element.ValueKind == JsonValueKind.String
            ? Result.Ok<string?, WebhookEnvelopeError>(element.GetString())
            : new WebhookEnvelopeError(name, "Value must be a string or null.");
    }

    private static Result<int, WebhookEnvelopeError> Integer(JsonElement root, string name, string? path = null)
    {
        var field = path ?? name;
        return root.TryGetProperty(name, out var element) &&
               element.ValueKind == JsonValueKind.Number &&
               element.TryGetInt32(out var value)
            ? value
            : new WebhookEnvelopeError(field, "Value must be an integer.");
    }

    private static Result<DateTimeOffset, WebhookEnvelopeError> Instant(JsonElement root, string name)
    {
        var raw = RequiredString(root, name);
        if (raw.IsFailure(out var error)) return error;

        var parsed = Wire.ParseInstant(raw.Get());
        return parsed.IsSuccess(out var instant)
            ? instant
            : new WebhookEnvelopeError(name, "Value must be an RFC 3339 instant.");
    }

    private static Result<DateTimeOffset?, WebhookEnvelopeError> OptionalInstant(JsonElement root, string name)
    {
        var raw = OptionalString(root, name);
        if (raw.IsFailure(out var error)) return error;
        if (raw.Get() is not { } text) return Result.Ok<DateTimeOffset?, WebhookEnvelopeError>(null);

        var parsed = Wire.ParseInstant(text);
        return parsed.IsSuccess(out var instant)
            ? Result.Ok<DateTimeOffset?, WebhookEnvelopeError>(instant)
            : new WebhookEnvelopeError(name, "Value must be an RFC 3339 instant or null.");
    }
}
