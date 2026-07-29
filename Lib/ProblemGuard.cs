using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.Problems;

/// <summary>Result-typed domain preconditions.</summary>
public static class ProblemGuard
{
    /// <summary>Returns the value when present, otherwise the supplied typed problem.</summary>
    public static Result<T, IDomainProblem> NotNull<T>(T? value, Func<IDomainProblem> problem)
        where T : class
    {
        ArgumentNullException.ThrowIfNull(problem);
        return value is null
            ? Result.Err<T, IDomainProblem>(problem())
            : Result.Ok<T, IDomainProblem>(value);
    }

    /// <summary>Returns Unit when the condition holds, otherwise the supplied typed problem.</summary>
    public static Result<Unit, IDomainProblem> Require(bool condition, Func<IDomainProblem> problem)
    {
        ArgumentNullException.ThrowIfNull(problem);
        return condition
            ? Result.Ok<Unit, IDomainProblem>(new Unit())
            : Result.Err<Unit, IDomainProblem>(problem());
    }

    /// <summary>Returns the value when present, otherwise a baseline EntityNotFound problem.</summary>
    public static Result<T, IDomainProblem> NotFound<T>(T? value, string id)
        where T : class =>
        NotNull(
            value,
            () => new EntityNotFound($"{typeof(T).Name} '{id}' was not found.", typeof(T), id));
}
