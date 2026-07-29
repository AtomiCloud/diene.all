using AtomiCloud.Diene.ApiEngine.Client;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ApiEngine.Calls;

/// <summary>
/// Wraps a call to a generated client so the call site receives
/// <c>Result&lt;T, Problem&gt;</c> instead of an exception.
/// </summary>
/// <remarks>
/// One line of ceremony per call, rather than a runtime proxy over the generated client: C#
/// has no analogue of a dynamic proxy that keeps static typing, and the alternatives fight
/// the type system for the sake of saving that line. This shape is generator-agnostic —
/// anything whose requests travel through the tree's <c>HttpClient</c> is classifiable.
/// </remarks>
public interface IApiCaller
{
    /// <summary>Wraps a call that returns a value.</summary>
    /// <remarks>
    /// No exception escapes. A call that fails for any reason — an upstream problem, a
    /// non-problem JSON failure, an unreachable host, a timeout, or a bug in the generated
    /// client — comes back as a failed Result.
    /// </remarks>
    Task<Result<T, Problem>> Call<T>(
        ServiceAddress address,
        Func<CancellationToken, Task<T>> call,
        CancellationToken cancellationToken = default);

    /// <summary>Wraps a call that returns nothing.</summary>
    Task<Result<Unit, Problem>> Call(
        ServiceAddress address,
        Func<CancellationToken, Task> call,
        CancellationToken cancellationToken = default);
}
