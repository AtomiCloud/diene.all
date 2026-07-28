using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>
/// Verifies a delivery's signature over its exact request bytes.
/// </summary>
/// <remarks>
/// The body arrives as a span of the RAW bytes, before any parsing, because that is what the
/// digest covers. Handing a verifier a deserialized object instead would make the check
/// re-serialization-dependent, and a byte the parser normalized away would break every
/// signature for reasons nobody could see.
/// </remarks>
public interface IWebhookSignatureVerifier
{
    /// <summary>
    /// Verifies the header against the body, returning the reason on refusal rather than a
    /// bare boolean so the caller can log which of the five distinct failures happened.
    /// </summary>
    Result<Unit, WebhookSignatureFailure> Verify(string? header, ReadOnlySpan<byte> body);
}
