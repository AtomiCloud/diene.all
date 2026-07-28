namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>
/// Why a delivery signature was refused. Every value ends in the same 401, and they stay
/// distinct so an operator can tell a clock-skew incident from a wrong-secret incident.
/// </summary>
public enum WebhookSignatureFailure
{
    /// <summary>The signature header was absent or empty.</summary>
    MissingHeader = 0,

    /// <summary>
    /// The header was present but did not carry exactly one well-formed <c>t</c> and
    /// <c>v1</c> parameter. Duplicate, unknown, and unparseable parameters land here.
    /// </summary>
    MalformedHeader = 1,

    /// <summary>The signed timestamp fell outside the accepted window.</summary>
    StaleTimestamp = 2,

    /// <summary>The digest did not match under any currently live rotation key.</summary>
    DigestMismatch = 3,

    /// <summary>
    /// The receiver holds no signing key, so it cannot verify anything. Distinct from a
    /// mismatch: nothing the caller sends could ever pass, and the fix is on this side.
    /// </summary>
    NoSigningKeys = 4,
}
