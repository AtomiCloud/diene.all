using System.Net;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using FluentAssertions.Execution;

namespace AtomiCloud.Diene.ServerEngine.TestHelper.Assertions;

/// <summary>
/// Assertions for the C0 §11 tri-state reply contract, stated as the contract states it.
/// </summary>
/// <remarks>
/// <para>
/// These exist because the two mistakes a receiver actually makes are both statuses that LOOK
/// fine: answering 404 for an event it does not own, and answering 421 for a signature it could
/// not verify. Mercury reads the first as a real endpoint failure and retries for 72 hours, and
/// the second as a stale address it should recompile — so both turn a clean refusal into an
/// operational incident. An assertion named after the contract's meaning refuses the wrong status
/// by construction; <c>StatusCode.Should().Be(421)</c> does not.
/// </para>
/// <para>
/// Every method asserts the EXACT status. C0 fixes exactly 200 for processed and exactly 421 for
/// not-mine, and treats every other 2xx as a real endpoint failure, so a success-range check would
/// pass a reply mercury would retry.
/// </para>
/// </remarks>
public static class WebhookResponseAssertions
{
    /// <summary>Asserts the delivery obligation was completed: exactly 200.</summary>
    public static HttpResponseMessage ShouldBeProcessed(this HttpResponseMessage response) =>
        Require(response, WebhookProtocol.ProcessedStatus, "processed");

    /// <summary>
    /// Asserts the receiver disowned the event with the only permitted signal: exactly 421.
    /// </summary>
    public static HttpResponseMessage ShouldBeNotMine(this HttpResponseMessage response) =>
        Require(response, WebhookProtocol.NotMineStatus, "not mine");

    /// <summary>Asserts the signature was refused: 401, never 421.</summary>
    public static HttpResponseMessage ShouldBeSignatureRejected(this HttpResponseMessage response) =>
        Require(response, (int)HttpStatusCode.Unauthorized, "signature rejected");

    /// <summary>Asserts the media type was refused: 415.</summary>
    public static HttpResponseMessage ShouldBeUnsupportedMedia(this HttpResponseMessage response) =>
        Require(response, (int)HttpStatusCode.UnsupportedMediaType, "unsupported media type");

    /// <summary>Asserts the envelope was refused as malformed: 400.</summary>
    public static HttpResponseMessage ShouldBeMalformedEnvelope(this HttpResponseMessage response) =>
        Require(response, (int)HttpStatusCode.BadRequest, "malformed envelope");

    private static HttpResponseMessage Require(HttpResponseMessage response, int expected, string meaning)
    {
        ArgumentNullException.ThrowIfNull(response);

        var actual = (int)response.StatusCode;
        var aside = actual == (int)HttpStatusCode.NotFound
            ? " 404 is never an ownership signal in this contract: mercury reads it as a real endpoint failure and retries for the full window."
            : string.Empty;

        Execute.Assertion
            .ForCondition(actual == expected)
            .FailWith(
                "Expected the delivery reply to mean {0} with status {1}, but found {2}.{3}",
                meaning,
                expected,
                actual,
                aside);

        return response;
    }
}
