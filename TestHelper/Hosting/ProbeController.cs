using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.ServerEngine.Mvc;
using Microsoft.AspNetCore.Mvc;

namespace AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;

/// <summary>The value a probe route returns on success.</summary>
/// <param name="Value">An echoed identifier.</param>
public sealed record ProbeValue(string Value);

/// <summary>
/// A controller with no domain behind it, whose only job is to drive
/// <see cref="AtomiController" /> and the exception-to-Problem filter.
/// </summary>
/// <remarks>
/// It ships in the TestHelper so a consumer can prove the filter is wired into ITS host — the
/// failure mode being that a service forgets the module registration and discovers at the first
/// production error that its problems render as bare 500s. Proving that needs a route whose
/// failure is known in advance, which a consumer's own controllers cannot provide.
/// </remarks>
[Route(RoutePrefix)]
public sealed class ProbeController : AtomiController
{
    /// <summary>The route prefix every probe route sits under.</summary>
    public const string RoutePrefix = "probe";

    private static readonly ProbeValue Known = new("known");

    /// <summary>Returns 200 through the synchronous resolve helper.</summary>
    [HttpGet("value/{id}")]
    public ActionResult<ProbeValue> Value(string id) => this.Resolve(Find(id));

    /// <summary>Returns 200 through the awaited resolve helper.</summary>
    [HttpGet("value-async/{id}")]
    public Task<ActionResult<ProbeValue>> ValueAsync(string id) => this.ResolveAsync(Task.FromResult(Find(id)));

    /// <summary>Returns 204 through the synchronous empty-resolve helper.</summary>
    [HttpDelete("value/{id}")]
    public ActionResult Erase(string id) => this.ResolveEmpty(Drop(id));

    /// <summary>Returns 204 through the awaited empty-resolve helper.</summary>
    [HttpDelete("value-async/{id}")]
    public Task<ActionResult> EraseAsync(string id) => this.ResolveEmptyAsync(Task.FromResult(Drop(id)));

    /// <summary>Echoes the request's correlation identifier.</summary>
    [HttpGet("trace")]
    public ActionResult<ProbeValue> Trace() => this.Ok(new ProbeValue(this.TraceId));

    /// <summary>Raises a typed problem the caller names, to exercise one catalog status.</summary>
    [HttpGet("problem/{kind}")]
    public ActionResult<ProbeValue> Problem(string kind) =>
        this.Resolve(Result.Err<ProbeValue, IDomainProblem>(ProblemFor(kind)));

    /// <summary>
    /// Throws an exception that is NOT a domain problem, so a test can prove the filter leaves it
    /// alone instead of dressing a real defect up as an expected refusal.
    /// </summary>
    [HttpGet("boom")]
    public ActionResult<ProbeValue> Boom() => throw new InvalidOperationException("probe boom");

    private static IDomainProblem ProblemFor(string kind) => kind switch
    {
        "conflict" => new EntityConflict("Probe conflict.", typeof(ProbeValue)),
        "unauthenticated" => new Unauthenticated("Probe is not authenticated."),
        "unregistered" => new ProbeUnregisteredProblem(),
        _ => new ValidationError(
            $"Probe does not know the problem kind '{kind}'.",
            new Dictionary<string, string[]>(StringComparer.Ordinal) { ["kind"] = [kind] }),
    };

    private static Result<ProbeValue, IDomainProblem> Find(string id) =>
        string.Equals(id, Known.Value, StringComparison.Ordinal)
            ? Result.Ok<ProbeValue, IDomainProblem>(Known)
            : Result.Err<ProbeValue, IDomainProblem>(
                new EntityNotFound($"Probe value '{id}' was not found.", typeof(ProbeValue), id));

    private static Result<Unit, IDomainProblem> Drop(string id) =>
        string.Equals(id, Known.Value, StringComparison.Ordinal)
            ? Result.Ok<Unit, IDomainProblem>(default)
            : Result.Err<Unit, IDomainProblem>(
                new EntityNotFound($"Probe value '{id}' was not found.", typeof(ProbeValue), id));
}
