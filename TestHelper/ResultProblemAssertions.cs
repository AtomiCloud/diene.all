using AtomiCloud.Diene.Results;
using FluentAssertions;
using FluentAssertions.Execution;

namespace AtomiCloud.Diene.Problems.TestHelper;

/// <summary>FluentAssertions entry points for Results with a domain-problem error channel.</summary>
public static class ResultProblemAssertionExtensions
{
    /// <summary>Creates assertions for a Result carrying IDomainProblem errors.</summary>
    public static ResultProblemAssertions<T> Should<T>(this Result<T, IDomainProblem> subject) => new(subject);
}

/// <summary>Assertions for Results carrying typed problems.</summary>
public sealed class ResultProblemAssertions<T>(Result<T, IDomainProblem> subject)
{
    /// <summary>Gets the assertion subject.</summary>
    public Result<T, IDomainProblem> Subject { get; } = subject;

    /// <summary>Asserts a failed Result carrying the requested typed problem.</summary>
    public AndWhichConstraint<ResultProblemAssertions<T>, TProblem> BeErrProblem<TProblem>(
        string because = "",
        params object[] becauseArgs)
        where TProblem : class, IDomainProblem
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.IsFailure())
            .FailWith("Expected result to carry a domain problem{reason}, but it was successful.");
        var problem = Subject.GetFailure();
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(problem is TProblem)
            .FailWith("Expected result problem to be {0}{reason}, but found {1}.", typeof(TProblem), problem.GetType());
        return new(this, (TProblem)problem);
    }
}
