namespace AtomiCloud.DotnetBase.Lib.Note;

/// <summary>
/// Persistence boundary owned by the note domain: the QUERY half, split out from
/// <see cref="INoteRepository"/> on purpose.
/// </summary>
/// <remarks>
/// A note store addressed only by key cannot serve these members honestly. Enumerating a
/// shared KV keyspace with <c>SCAN note:*</c> is not a listing primitive — it is an O(keyspace)
/// walk whose cost belongs to every other tenant of that instance — and looking a note up by
/// title needs a secondary index a KV store does not have. Rather than let a KV adapter answer
/// with a stub, it does not implement this interface at all, so the limitation is a compile
/// error at the wiring rather than a surprise at runtime.
/// </remarks>
public interface INoteCatalogue
{
    /// <summary>Reads every note.</summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Every stored note, in a stable order.</returns>
    Task<IReadOnlyList<NotePrincipal>> All(CancellationToken cancellationToken = default);

    /// <summary>Reads the single note carrying a title. Titles are unique.</summary>
    /// <param name="title">The title to look for.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The note, or <see langword="null"/> when no note carries that title.</returns>
    Task<NotePrincipal?> FindByTitle(string title, CancellationToken cancellationToken = default);
}
