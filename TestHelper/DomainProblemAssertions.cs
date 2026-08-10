using FluentAssertions;
using FluentAssertions.Execution;

namespace AtomiCloud.Diene.Problems.TestHelper;

/// <summary>FluentAssertions entry points for typed domain problems.</summary>
public static class DomainProblemAssertionExtensions
{
    /// <summary>Creates assertions for a domain problem.</summary>
    public static DomainProblemAssertions Should(this IDomainProblem subject) => new(subject);
}

/// <summary>Assertions over domain-problem identity and payload type.</summary>
public sealed class DomainProblemAssertions(IDomainProblem subject)
{
    /// <summary>Gets the assertion subject.</summary>
    public IDomainProblem Subject { get; } = subject ?? throw new ArgumentNullException(nameof(subject));

    /// <summary>Asserts the concrete typed problem.</summary>
    public AndWhichConstraint<DomainProblemAssertions, TProblem> BeProblem<TProblem>(
        string because = "",
        params object[] becauseArgs)
        where TProblem : class, IDomainProblem
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject is TProblem)
            .FailWith("Expected problem to be {0}{reason}, but found {1}.", typeof(TProblem), Subject.GetType());
        return new(this, (TProblem)Subject);
    }

    /// <summary>Asserts the stable snake_case wire identifier.</summary>
    public AndConstraint<DomainProblemAssertions> HaveId(
        string expected,
        string because = "",
        params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.Id == expected)
            .FailWith("Expected problem id to be {0}{reason}, but found {1}.", expected, Subject.Id);
        return new(this);
    }

    /// <summary>Asserts the versioned problem identity.</summary>
    public AndConstraint<DomainProblemAssertions> HaveVersion(
        string expected,
        string because = "",
        params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.Version == expected)
            .FailWith("Expected problem version to be {0}{reason}, but found {1}.", expected, Subject.Version);
        return new(this);
    }
}
