using FluentAssertions;
using FluentAssertions.Execution;
using FluentAssertions.Specialized;

namespace AtomiCloud.Diene.Problems.TestHelper;

/// <summary>Assertions for exceptions carrying typed domain problems.</summary>
public static class DomainProblemExceptionAssertions
{
    /// <summary>Asserts the problem type carried by a DomainProblemException.</summary>
    public static AndWhichConstraint<ExceptionAssertions<DomainProblemException>, TProblem> WithProblem<TProblem>(
        this ExceptionAssertions<DomainProblemException> assertions,
        Action<TProblem>? inspect = null,
        string because = "",
        params object[] becauseArgs)
        where TProblem : class, IDomainProblem
    {
        ArgumentNullException.ThrowIfNull(assertions);
        var actual = assertions.Which.Problem;
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(actual is TProblem)
            .FailWith("Expected exception problem to be {0}{reason}, but found {1}.", typeof(TProblem), actual.GetType());
        var typed = (TProblem)actual;
        inspect?.Invoke(typed);
        return new(assertions, typed);
    }
}
