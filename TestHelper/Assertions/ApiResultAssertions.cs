using System.Text.Json;
using AtomiCloud.Diene.ApiEngine.Upstreams;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ApiEngine.TestHelper.Assertions;

/// <summary>
/// Assertions over a wrapped call's outcome, so a consumer does not re-derive the same
/// unwrapping and payload-decoding in every test.
/// </summary>
/// <remarks>
/// The value these add over generic Result and problem-envelope assertions is the typed
/// <c>data</c> payload: telling an upstream that answered badly apart from one that did not
/// answer means reading this engine's own problem types out of the envelope, and doing that by
/// hand in each test is how a suite ends up asserting on the wrong one.
/// </remarks>
public static class ApiResultAssertions
{
    /// <summary>Asserts the call succeeded, and returns its value.</summary>
    public static T ShouldBeOk<T>(this Result<T, Problem> subject)
    {
        if (subject.IsFailure(out var problem))
        {
            throw new ApiAssertionException(
                $"Expected a successful call but found problem '{problem.Type}' " +
                $"(status {problem.Status}): {problem.Detail}");
        }

        return subject.Get();
    }

    /// <summary>Asserts the call failed, and returns the problem envelope.</summary>
    public static Problem ShouldBeProblem<T>(this Result<T, Problem> subject)
    {
        if (subject.IsSuccess(out var value))
        {
            throw new ApiAssertionException($"Expected a failed call but it returned '{value}'.");
        }

        return subject.GetFailure();
    }

    /// <summary>
    /// Asserts the call failed because the upstream answered with a non-problem JSON body, and
    /// returns that typed payload.
    /// </summary>
    public static UpstreamRejected ShouldBeUpstreamRejected<T>(this Result<T, Problem> subject) =>
        subject.ShouldBeProblem().Payload<UpstreamRejected>();

    /// <summary>
    /// Asserts the call failed because no interpretable answer arrived, and returns that typed
    /// payload.
    /// </summary>
    public static UpstreamTransportFailure ShouldBeTransportFailure<T>(this Result<T, Problem> subject) =>
        subject.ShouldBeProblem().Payload<UpstreamTransportFailure>();

    /// <summary>
    /// Asserts the failure is the upstream's OWN problem, passed through unaltered, and returns
    /// it.
    /// </summary>
    /// <remarks>
    /// Checked by type URI rather than by the absence of this engine's payload: a passthrough is
    /// defined by carrying the originating service's contract identity, and asserting on what it
    /// is not would also accept an envelope this engine had rewritten.
    /// </remarks>
    public static Problem ShouldBePassedThrough<T>(this Result<T, Problem> subject, string expectedType)
    {
        var problem = subject.ShouldBeProblem();
        if (!string.Equals(problem.Type, expectedType, StringComparison.Ordinal))
        {
            throw new ApiAssertionException(
                $"Expected the upstream problem '{expectedType}' to be passed through but found '{problem.Type}'.");
        }

        return problem;
    }

    /// <summary>Asserts the envelope's HTTP status.</summary>
    public static Problem ShouldHaveStatus(this Problem subject, int expected)
    {
        ArgumentNullException.ThrowIfNull(subject);
        if (subject.Status != expected)
        {
            throw new ApiAssertionException(
                $"Expected problem status {expected} but found {subject.Status} for '{subject.Type}'.");
        }

        return subject;
    }

    /// <remarks>
    /// The problem's IDENTITY is checked before its payload is decoded, and that ordering is
    /// load-bearing. Deserializing a transport-failure payload into <c>UpstreamRejected</c> SUCCEEDS —
    /// unknown members are ignored and absent ones default — so a decode-only assertion returns a
    /// zero-filled object instead of failing, and can never distinguish the two problems it exists to
    /// distinguish. The type URI is the contract identity, so it is what discriminates.
    /// </remarks>
    private static TPayload Payload<TPayload>(this Problem subject)
        where TPayload : class, IDomainProblem, new()
    {
        var expected = new TPayload();
        var identity = $"/{expected.Version}/{expected.Id}";
        if (!subject.Type.EndsWith(identity, StringComparison.Ordinal))
        {
            throw new ApiAssertionException(
                $"Expected a '{expected.Id}' problem but found type '{subject.Type}'.");
        }

        if (subject.Data is null)
        {
            throw new ApiAssertionException(
                $"Expected the '{expected.Id}' payload in problem data but the data was absent " +
                $"(type '{subject.Type}').");
        }

        try
        {
            // Non-null after the guard above: a JsonNode cannot represent a JSON null — an absent value
            // arrives as a null reference, which the guard already rejected — so a successful decode of
            // a present node always yields an instance.
            return subject.Data.Deserialize<TPayload>(AtomiJson.DefaultOptions)!;
        }
        catch (JsonException exception)
        {
            throw new ApiAssertionException(
                $"Expected the '{expected.Id}' payload in problem data but it did not decode: " +
                $"{subject.Data.ToJsonString()}",
                exception);
        }
    }
}
