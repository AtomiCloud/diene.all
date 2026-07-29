namespace AtomiCloud.DotnetBase.Lib.Note;

/// <summary>
/// Persistence boundary owned by the note domain: the KEYED half. Every member here is
/// something any store addressable by note id can serve honestly, which is why the KV adapter
/// implements all of it. Enumeration and lookup-by-title are deliberately NOT here — they live
/// on <see cref="INoteCatalogue"/>, which a KV store does not implement.
/// </summary>
public interface INoteRepository
{
    /// <summary>Persists new content under a freshly minted identity.</summary>
    /// <param name="record">The content to store.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The stored note, carrying its assigned identity.</returns>
    Task<NotePrincipal> Save(NoteRecord record, CancellationToken cancellationToken = default);

    /// <summary>Reads a note by identity.</summary>
    /// <param name="id">The note identity.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The note, or <see langword="null"/> when no note carries that identity.</returns>
    Task<NotePrincipal?> Find(string id, CancellationToken cancellationToken = default);

    /// <summary>
    /// Overwrites the content of an existing note. This is a replace, never an upsert: a missing
    /// note is reported rather than created, so a caller cannot silently resurrect a deletion.
    /// </summary>
    /// <param name="id">The note identity.</param>
    /// <param name="record">The replacement content.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The updated note, or <see langword="null"/> when no note carries that identity.</returns>
    Task<NotePrincipal?> Replace(string id, NoteRecord record, CancellationToken cancellationToken = default);

    /// <summary>Deletes a note by identity.</summary>
    /// <param name="id">The note identity.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>
    /// <see langword="true"/> when a note was deleted, <see langword="false"/> when there was
    /// none to delete. The distinction is the caller's, so deletion can be reported as
    /// not-found rather than pretended to have succeeded.
    /// </returns>
    Task<bool> Remove(string id, CancellationToken cancellationToken = default);
}
