using System.Text.Json;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.CoreUtils.Json;
using FluentAssertions;
using FluentAssertions.Execution;
using FluentAssertions.Primitives;

namespace AtomiCloud.Diene.Problems.TestHelper;

/// <summary>Assertions for an end-to-end RFC 9457 HTTP response.</summary>
public static class HttpResponseProblemAssertions
{
    private static readonly string[] RequiredMembers =
        ["type", "title", "status", "detail", "instance", "data", "recoverable"];

    /// <summary>Asserts content type, required members, status parity, and deserializes the envelope.</summary>
    public static async Task<AndWhichConstraint<HttpResponseMessageAssertions, Problem>> BeRfc9457(
        this HttpResponseMessageAssertions assertions,
        string because = "",
        params object[] becauseArgs)
    {
        ArgumentNullException.ThrowIfNull(assertions);
        var subject = assertions.Subject;
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(subject.Content.Headers.ContentType?.MediaType == "application/problem+json")
            .FailWith(
                "Expected response content type to be application/problem+json{reason}, but found {0}.",
                subject.Content.Headers.ContentType?.MediaType);

        var body = await subject.Content.ReadAsStringAsync().ConfigureAwait(false);
        var document = JsonNode.Parse(body) as JsonObject;
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(document is not null && RequiredMembers.All(document.ContainsKey))
            .FailWith("Expected response to contain all RFC 9457 and Diene extension members{reason}, but found {0}.", body);

        var envelope = JsonSerializer.Deserialize<Problem>(body, AtomiJson.DefaultOptions);
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(envelope is not null && envelope.Status == (int)subject.StatusCode)
            .FailWith("Expected envelope status to match HTTP status{reason}, but found {0}.", body);
        return new(assertions, envelope!);
    }
}
