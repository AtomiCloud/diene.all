using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.ServerEngine.Mvc;
using Microsoft.AspNetCore.Mvc;

namespace AtomiCloud.DotnetBase.App;

/// <summary>A note the demo domain returns.</summary>
/// <param name="Id">The note identifier.</param>
/// <param name="Title">The note title.</param>
public sealed record DemoNote(string Id, string Title);

/// <summary>
/// A consumer controller, showing what a service's own controllers look like on top of
/// <see cref="AtomiController" />.
/// </summary>
/// <remarks>
/// It uses all four resolve helpers deliberately: a demo that exercised only the synchronous
/// one would leave the async pair proven by tests alone, and the strict production dead-code
/// pass — which excludes test projects — is what makes that gap visible.
/// </remarks>
[Route("notes")]
public sealed class DemoNotesController : AtomiController
{
    private static readonly DemoNote Known = new("note-1", "Hello");

    /// <summary>Returns a note synchronously, or the typed not-found problem.</summary>
    [HttpGet("{id}")]
    public ActionResult<DemoNote> Get(string id) => this.Resolve(Find(id));

    /// <summary>Returns a note through the awaited overload.</summary>
    [HttpGet("{id}/async")]
    public Task<ActionResult<DemoNote>> GetAsync(string id) => this.ResolveAsync(Task.FromResult(Find(id)));

    /// <summary>Deletes a note, answering 204 on success.</summary>
    [HttpDelete("{id}")]
    public ActionResult Delete(string id) => this.ResolveEmpty(Erase(id));

    /// <summary>Deletes a note through the awaited overload.</summary>
    [HttpDelete("{id}/async")]
    public Task<ActionResult> DeleteAsync(string id) => this.ResolveEmptyAsync(Task.FromResult(Erase(id)));

    /// <summary>Echoes the request's correlation identifier.</summary>
    [HttpGet("trace")]
    public ActionResult<string> Trace() => this.Ok(this.TraceId);

    /// <summary>Raises a problem that is not registered in the catalog.</summary>
    [HttpGet("{id}/unregistered")]
    public ActionResult<DemoNote> Unregistered(string id) =>
        this.Resolve(Result.Err<DemoNote, IDomainProblem>(new DemoUnregisteredProblem(id)));

    private static Result<DemoNote, IDomainProblem> Find(string id) =>
        string.Equals(id, Known.Id, StringComparison.Ordinal)
            ? Result.Ok<DemoNote, IDomainProblem>(Known)
            : Result.Err<DemoNote, IDomainProblem>(
                new EntityNotFound($"Note '{id}' was not found.", typeof(DemoNote), id));

    private static Result<Unit, IDomainProblem> Erase(string id) =>
        string.Equals(id, Known.Id, StringComparison.Ordinal)
            ? Result.Ok<Unit, IDomainProblem>(default)
            : Result.Err<Unit, IDomainProblem>(
                new EntityNotFound($"Note '{id}' was not found.", typeof(DemoNote), id));
}
