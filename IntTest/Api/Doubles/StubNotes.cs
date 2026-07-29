using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using AtomiCloud.DotnetBase.Lib.Note;

namespace AtomiCloud.DotnetBase.IntTest.Api.Doubles;

/// <summary>
/// An <see cref="INotes"/> that answers however a test needs, so the error tiers can be reached
/// through the REAL HTTP pipeline without a container.
/// </summary>
/// <remarks>
/// Substituting at the domain-service seam rather than the repository is what makes the raw
/// exception and unregistered-problem tiers reachable at all: a repository cannot return a
/// problem, and provoking a driver-level exception on demand would mean breaking a container
/// mid-suite. The pipeline under test — routing, the filter, negotiation, the envelope — is
/// identical either way.
/// </remarks>
/// <param name="answer">The failure to answer with, or null to throw <paramref name="thrown"/>.</param>
/// <param name="thrown">The exception to throw when <paramref name="answer"/> is null.</param>
internal sealed class StubNotes(IDomainProblem? answer, Exception? thrown = null) : INotes
{
    /// <inheritdoc />
    public Task<Result<NotePrincipal, IDomainProblem>> Get(
        string id,
        CancellationToken cancellationToken = default) => this.Fail<NotePrincipal>();

    /// <inheritdoc />
    public Task<Result<NotePrincipal, IDomainProblem>> Create(
        NoteRecord record,
        CancellationToken cancellationToken = default) => this.Fail<NotePrincipal>();

    /// <inheritdoc />
    public Task<Result<NotePrincipal, IDomainProblem>> Update(
        string id,
        NoteRecord record,
        CancellationToken cancellationToken = default) => this.Fail<NotePrincipal>();

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> Delete(
        string id,
        CancellationToken cancellationToken = default) => this.Fail<Unit>();

    /// <inheritdoc />
    public Task<Result<IReadOnlyList<NotePrincipal>, IDomainProblem>> List(
        CancellationToken cancellationToken = default) => this.Fail<IReadOnlyList<NotePrincipal>>();

    private Task<Result<T, IDomainProblem>> Fail<T>() => answer is null
        ? throw thrown ?? new InvalidOperationException("StubNotes needs a problem or an exception.")
        : Task.FromResult(Result.Err<T, IDomainProblem>(answer));
}

/// <summary>
/// A typed problem that NO catalog registers. The library renders it as 500 with an
/// <c>about:blank</c> type and logs the catalog defect, which is the correct behaviour and is
/// worth pinning: a fallback status invented here would hide a real registration mistake.
/// </summary>
internal sealed class UnregisteredProblem : IDomainProblem
{
    /// <inheritdoc />
    public string Id => "int_test_unregistered";

    /// <inheritdoc />
    public string Title => "Unregistered by design";

    /// <inheritdoc />
    public string Detail => "This problem is deliberately absent from the catalog.";

    /// <inheritdoc />
    public string Version => "v1";
}
