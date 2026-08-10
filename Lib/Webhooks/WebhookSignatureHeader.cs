using System.Globalization;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>The parsed contents of one <c>X-Atomi-Webhook-Signature</c> header.</summary>
/// <param name="Timestamp">The signed Unix timestamp in whole seconds.</param>
/// <param name="Digest">The 32 raw bytes decoded from the <c>v1</c> parameter.</param>
internal sealed record WebhookSignatureHeader(long Timestamp, byte[] Digest)
{
    private const int DigestHexLength = 64;

    /// <summary>
    /// Parses the header strictly: exactly one <c>t</c> and one <c>v1</c>, optional
    /// whitespace around them, and nothing else.
    /// </summary>
    /// <remarks>
    /// Strictness is the point. C0 fails verification on duplicate, missing, malformed, AND
    /// unknown parameters, so a lenient parser that ignored an extra parameter would accept a
    /// header a signer never intended — and a second <c>v1</c> is precisely how an attacker
    /// would try to smuggle a digest past a first-match parser.
    /// </remarks>
    internal static Result<WebhookSignatureHeader, WebhookSignatureFailure> Parse(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return Result.Err<WebhookSignatureHeader, WebhookSignatureFailure>(
                WebhookSignatureFailure.MissingHeader);
        }

        string? stamp = null;
        string? digest = null;

        foreach (var part in value.Split(','))
        {
            var pair = part.Split('=');
            if (pair.Length != 2) return Malformed();

            var name = pair[0].Trim();
            var content = pair[1].Trim();

            switch (name)
            {
                case "t" when stamp is null:
                    stamp = content;
                    break;
                case "v1" when digest is null:
                    digest = content;
                    break;
                default:
                    return Malformed();
            }
        }

        if (stamp is null || digest is null) return Malformed();

        // NumberStyles.None rejects a sign, whitespace, and group separators, which is what
        // "unsigned base-10 Unix timestamp in whole seconds" means. long.TryParse's default
        // styles would accept "-1" and " 1 ".
        if (!long.TryParse(stamp, NumberStyles.None, CultureInfo.InvariantCulture, out var seconds))
        {
            return Malformed();
        }

        if (digest.Length != DigestHexLength || !digest.All(IsLowerHex)) return Malformed();

        return Result.Ok<WebhookSignatureHeader, WebhookSignatureFailure>(
            new WebhookSignatureHeader(seconds, Convert.FromHexString(digest)));
    }

    private static bool IsLowerHex(char candidate) => candidate is >= '0' and <= '9' or >= 'a' and <= 'f';

    private static Result<WebhookSignatureHeader, WebhookSignatureFailure> Malformed() =>
        Result.Err<WebhookSignatureHeader, WebhookSignatureFailure>(WebhookSignatureFailure.MalformedHeader);
}
