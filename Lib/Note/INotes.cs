using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.DotnetBase.Lib.Note;

/// <summary>
/// The note domain service. Every failure here is a VALUE, never a null and never an exception,
/// because the API layer resolves a <c>Result&lt;T, IDomainProblem&gt;</c> straight onto the wire
/// through the shipped problem filter. A repository that answers <see langword="null"/> for a
/// missing row is correct at the persistence boundary; it is this layer's job to turn that into
/// a typed problem before it can reach a caller.
/// </summary>
public interface INotes
{
    /// <summary>Reads one note.</summary>
    /// <param name="id">The note identity.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The note, or <c>entity_not_found</c>.</returns>
    Task<Result<NotePrincipal, IDomainProblem>> Get(string id, CancellationToken cancellationToken = default);

    /// <summary>Creates a note. Titles are unique across the store.</summary>
    /// <param name="record">The content to store.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The created note, or <c>entity_conflict</c> when the title is already used.</returns>
    Task<Result<NotePrincipal, IDomainProblem>> Create(NoteRecord record, CancellationToken cancellationToken = default);

    /// <summary>Replaces the content of an existing note. Never creates one.</summary>
    /// <param name="id">The note identity.</param>
    /// <param name="record">The replacement content.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>
    /// The updated note, <c>entity_not_found</c> when there is no such note, or
    /// <c>entity_conflict</c> when the new title belongs to a DIFFERENT note.
    /// </returns>
    Task<Result<NotePrincipal, IDomainProblem>> Update(
        string id,
        NoteRecord record,
        CancellationToken cancellationToken = default);

    /// <summary>Deletes a note.</summary>
    /// <param name="id">The note identity.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Nothing on success, or <c>entity_not_found</c> when there was nothing to delete.</returns>
    Task<Result<Unit, IDomainProblem>> Delete(string id, CancellationToken cancellationToken = default);

    /// <summary>Reads every note.</summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Every stored note. An empty store is an empty list, not a problem.</returns>
    Task<Result<IReadOnlyList<NotePrincipal>, IDomainProblem>> List(CancellationToken cancellationToken = default);
}
