using System.Text.Json;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.CoreUtils.Json;
using FluentAssertions;
using FluentAssertions.Execution;

namespace AtomiCloud.Diene.Problems.TestHelper;

/// <summary>FluentAssertions entry points for RFC 9457 wire envelopes.</summary>
public static class ProblemEnvelopeAssertionExtensions
{
    /// <summary>Creates assertions for a problem envelope.</summary>
    public static ProblemEnvelopeAssertions Should(this Problem subject) => new(subject);
}

/// <summary>Assertions over type URI, status, recoverability, and typed data.</summary>
public sealed class ProblemEnvelopeAssertions(Problem subject)
{
    /// <summary>Gets the assertion subject.</summary>
    public Problem Subject { get; } = subject ?? throw new ArgumentNullException(nameof(subject));

    /// <summary>Asserts the RFC 9457 type URI.</summary>
    public AndConstraint<ProblemEnvelopeAssertions> HaveType(
        string expected,
        string because = "",
        params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.Type == expected)
            .FailWith("Expected problem type to be {0}{reason}, but found {1}.", expected, Subject.Type);
        return new(this);
    }

    /// <summary>Asserts the HTTP status.</summary>
    public AndConstraint<ProblemEnvelopeAssertions> HaveStatus(
        int expected,
        string because = "",
        params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.Status == expected)
            .FailWith("Expected problem status to be {0}{reason}, but found {1}.", expected, Subject.Status);
        return new(this);
    }

    /// <summary>Asserts the typed <c>data</c> extension.</summary>
    public AndWhichConstraint<ProblemEnvelopeAssertions, TData> HaveData<TData>(
        TData expected,
        string because = "",
        params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.Data is not null)
            .FailWith("Expected problem data to be present{reason}, but it was null.");
        var expectedData = JsonSerializer.SerializeToNode(expected, AtomiJson.DefaultOptions);
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(JsonNode.DeepEquals(Subject.Data, expectedData))
            .FailWith(
                "Expected problem data to equal {0}{reason}, but found {1}.",
                expectedData?.ToJsonString(),
                Subject.Data?.ToJsonString());
        var actual = Subject.Data!.Deserialize<TData>(AtomiJson.DefaultOptions);
        return new(this, actual!);
    }

    /// <summary>Asserts the recoverability extension.</summary>
    public AndConstraint<ProblemEnvelopeAssertions> BeRecoverable(
        bool expected,
        string because = "",
        params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.Recoverable == expected)
            .FailWith("Expected problem recoverable to be {0}{reason}, but found {1}.", expected, Subject.Recoverable);
        return new(this);
    }
}
