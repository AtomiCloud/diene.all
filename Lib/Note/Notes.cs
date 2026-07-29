using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.DotnetBase.Lib.Note;

/// <summary>
/// The note domain service over the two persistence ports. It owns exactly one thing the
/// adapters cannot: turning "there is no such row" and "that title is taken" from a
/// <see langword="null"/> and a race into typed problems the API layer can resolve.
/// </summary>
/// <remarks>
/// Uniqueness is enforced in TWO places on purpose and they are not redundant. The read-then-write
/// check here exists so the ordinary collision answers a typed 409 naming the title; the unique
/// index in the store exists because this check is not atomic and two concurrent creates can both
/// pass it. Removing either one is a downgrade — the check alone is racy, the index alone can only
/// fail as a driver exception.
/// </remarks>
/// <param name="repository">The keyed store.</param>
/// <param name="catalogue">The query side. Only a store with an index implements it.</param>
public sealed class Notes(INoteRepository repository, INoteCatalogue catalogue) : INotes
{
    /// <inheritdoc />
    public async Task<Result<NotePrincipal, IDomainProblem>> Get(
        string id,
        CancellationToken cancellationToken = default)
    {
        var found = await repository.Find(id, cancellationToken).ConfigureAwait(false);
        return found is null ? Missing(id) : Result.Ok<NotePrincipal, IDomainProblem>(found);
    }

    /// <inheritdoc />
    public async Task<Result<NotePrincipal, IDomainProblem>> Create(
        NoteRecord record,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(record);

        var holder = await catalogue.FindByTitle(record.Title, cancellationToken).ConfigureAwait(false);
        if (holder is not null) return Taken(record.Title);

        var saved = await repository.Save(record, cancellationToken).ConfigureAwait(false);
        return Result.Ok<NotePrincipal, IDomainProblem>(saved);
    }

    /// <inheritdoc />
    public async Task<Result<NotePrincipal, IDomainProblem>> Update(
        string id,
        NoteRecord record,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(record);

        // A note keeping its own title is not a conflict with itself, which is why this compares
        // identity rather than just testing for a holder the way Create does.
        var holder = await catalogue.FindByTitle(record.Title, cancellationToken).ConfigureAwait(false);
        if (holder is not null && !string.Equals(holder.Id, id, StringComparison.Ordinal))
            return Taken(record.Title);

        var updated = await repository.Replace(id, record, cancellationToken).ConfigureAwait(false);
        return updated is null ? Missing(id) : Result.Ok<NotePrincipal, IDomainProblem>(updated);
    }

    /// <inheritdoc />
    public async Task<Result<Unit, IDomainProblem>> Delete(
        string id,
        CancellationToken cancellationToken = default)
    {
        var removed = await repository.Remove(id, cancellationToken).ConfigureAwait(false);
        return removed
            ? Result.Ok<Unit, IDomainProblem>(default)
            : Result.Err<Unit, IDomainProblem>(NotFound(id));
    }

    /// <inheritdoc />
    public async Task<Result<IReadOnlyList<NotePrincipal>, IDomainProblem>> List(
        CancellationToken cancellationToken = default)
    {
        var all = await catalogue.All(cancellationToken).ConfigureAwait(false);
        return Result.Ok<IReadOnlyList<NotePrincipal>, IDomainProblem>(all);
    }

    private static Result<NotePrincipal, IDomainProblem> Missing(string id) =>
        Result.Err<NotePrincipal, IDomainProblem>(NotFound(id));

    private static Result<NotePrincipal, IDomainProblem> Taken(string title) =>
        Result.Err<NotePrincipal, IDomainProblem>(
            new EntityConflict($"A note titled '{title}' already exists.", typeof(NotePrincipal)));

    private static EntityNotFound NotFound(string id) =>
        new($"No note carries the id '{id}'.", typeof(NotePrincipal), id);
}
