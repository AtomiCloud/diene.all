using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.Problems;

/// <summary>Adapters for the Result error channel and the ASP.NET exception boundary.</summary>
public static class DomainProblemExtensions
{
    /// <summary>Wraps a domain problem for transport through an exception-handling pipeline.</summary>
    public static DomainProblemException ToException(this IDomainProblem problem) => new(problem);

    /// <summary>Creates a failed Result carrying the domain problem.</summary>
    public static Result<T, IDomainProblem> ToErr<T>(this IDomainProblem problem) =>
        Result.Err<T, IDomainProblem>(problem ?? throw new ArgumentNullException(nameof(problem)));
}
