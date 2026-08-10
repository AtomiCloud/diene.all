using System.Text.Json;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.ApiEngine.Upstreams;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.Diene.ApiEngine.Calls;

/// <summary>
/// Turns a failed exchange into exactly one <see cref="Problem" />. HTTP has no result type
/// — only statuses, streams, and arbitrary bytes — and this is where that gap is closed.
/// </summary>
/// <remarks>
/// The three outcomes are deliberately distinct problems, not three details of one:
/// an upstream problem envelope is passed through so the originating service's contract
/// reaches the caller unaltered; a JSON body that is not a problem becomes
/// <see cref="UpstreamRejected" />; anything unreadable becomes
/// <see cref="UpstreamTransportFailure" />.
/// </remarks>
internal static class ApiResponseClassifier
{
    /// <summary>How deep a wrapper may nest a problem envelope before it is not one.</summary>
    /// <remarks>
    /// Bounded rather than unlimited: an unbounded search would eventually find something
    /// problem-shaped inside an arbitrary payload and report an unrelated object as the
    /// failure, which is worse than declining to recognise it.
    /// </remarks>
    internal const int MaxNestingDepth = 4;

    /// <summary>Classifies a failed exchange, or the absence of one.</summary>
    internal static Problem Classify(
        string upstream,
        ApiFailure? failure,
        int attempts,
        bool rescuable,
        string reason,
        IProblemTypeUriBuilder typeUris)
    {
        if (failure is null)
        {
            return Transport(upstream, null, null, null, attempts, rescuable, reason, typeUris);
        }

        if (string.IsNullOrWhiteSpace(failure.Body))
        {
            // The snippet is dropped rather than carried: a body of nothing but whitespace is being
            // reported as "no body to interpret", and a payload that then shows three spaces
            // contradicts its own detail.
            return Transport(
                upstream,
                failure.Status,
                failure.ContentType,
                null,
                attempts,
                rescuable,
                $"{reason} The upstream returned no body to interpret.",
                typeUris);
        }

        // Parsed rather than sniffed by media type on purpose: a service that sends a
        // problem envelope under application/json is still sending a problem, and one that
        // claims application/problem+json while sending an HTML error page is not. The bytes
        // decide.
        if (!TryParse(failure.Body, out var node))
        {
            return Transport(
                upstream,
                failure.Status,
                failure.ContentType,
                failure.Body,
                attempts,
                rescuable,
                $"{reason} The upstream body could not be read as JSON.",
                typeUris);
        }

        // The body is non-null here: the blank guard above has already returned for null, empty, and
        // whitespace, so the rejection path receives a real string rather than a defaulted one.
        return TryFindProblem(node, 0, out var envelope)
            ? Passthrough(envelope)
            : Rejected(upstream, failure, failure.Body!, typeUris);
    }

    private static bool TryParse(string body, out JsonNode node)
    {
        try
        {
            var parsed = JsonNode.Parse(body);
            if (parsed is null)
            {
                node = JsonValue.Create(0);
                return false;
            }

            node = parsed;
            return true;
        }
        catch (JsonException)
        {
            node = JsonValue.Create(0);
            return false;
        }
    }

    /// <summary>
    /// Finds the problem envelope in a body, whether it is the body itself or nested inside
    /// a wrapper an upstream put around it.
    /// </summary>
    private static bool TryFindProblem(JsonNode node, int depth, out JsonObject envelope)
    {
        envelope = [];
        if (depth > MaxNestingDepth || node is not JsonObject candidate) return false;

        if (IsProblem(candidate))
        {
            envelope = candidate;
            return true;
        }

        foreach (var (_, child) in candidate)
        {
            if (child is not null && TryFindProblem(child, depth + 1, out envelope)) return true;
        }

        envelope = [];
        return false;
    }

    /// <summary>
    /// The minimal structural contract for an RFC 9457 envelope: a type URI, a title, and a
    /// numeric status.
    /// </summary>
    /// <remarks>
    /// All three are required together because any one alone is a common member name in
    /// ordinary payloads, and matching on one would classify arbitrary JSON as a problem.
    /// </remarks>
    private static bool IsProblem(JsonObject candidate) =>
        IsString(candidate, "type") && IsString(candidate, "title") && IsInteger(candidate, "status");

    private static bool IsString(JsonObject candidate, string member) =>
        candidate.TryGetPropertyValue(member, out var value) &&
        value is JsonValue text &&
        text.TryGetValue<string>(out _);

    private static bool IsInteger(JsonObject candidate, string member) =>
        candidate.TryGetPropertyValue(member, out var value) &&
        value is JsonValue number &&
        number.TryGetValue<int>(out _);

    /// <remarks>
    /// Non-null by construction: the argument is a <see cref="JsonObject" /> that already satisfied the
    /// envelope predicate, and deserializing a present object never yields null.
    /// </remarks>
    private static Problem Passthrough(JsonObject envelope) =>
        envelope.Deserialize<Problem>(AtomiJson.DefaultOptions)!;

    private static Problem Rejected(
        string upstream,
        ApiFailure failure,
        string body,
        IProblemTypeUriBuilder typeUris)
    {
        var problem = new UpstreamRejected(
            $"Upstream '{upstream}' returned status {failure.Status} with a JSON body that is not a problem envelope.",
            upstream,

            // Zero when a body arrived with no status attached. A rejection is defined by the upstream
            // having ANSWERED, and a caller reading 0 can tell that the status was absent rather than
            // being handed a plausible-looking substitute.
            failure.Status ?? 0,
            failure.ContentType,
            body);
        return Envelope(
            problem,
            ApiEngineProblems.UpstreamRejectedStatus,
            ApiEngineProblems.UpstreamRejectedRecoverable,
            typeUris);
    }

    private static Problem Transport(
        string upstream,
        int? status,
        string? contentType,
        string? body,
        int attempts,
        bool rescuable,
        string detail,
        IProblemTypeUriBuilder typeUris)
    {
        var problem = new UpstreamTransportFailure(
            detail,
            upstream,
            status,
            contentType,
            body,
            attempts,
            rescuable);
        return Envelope(
            problem,
            ApiEngineProblems.UpstreamTransportFailureStatus,
            ApiEngineProblems.UpstreamTransportFailureRecoverable,
            typeUris);
    }

    private static Problem Envelope(
        IDomainProblem problem,
        int status,
        bool recoverable,
        IProblemTypeUriBuilder typeUris) =>
        new()
        {
            Type = typeUris.Build(problem.Version, problem.Id).AbsoluteUri,
            Title = problem.Title,
            Status = status,
            Detail = problem.Detail,
            Recoverable = recoverable,
            Data = JsonSerializer.SerializeToNode(problem, problem.GetType(), AtomiJson.DefaultOptions),
        };
}
