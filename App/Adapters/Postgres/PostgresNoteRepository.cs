using AtomiCloud.DotnetBase.Lib.Note;
using Microsoft.EntityFrameworkCore;

namespace AtomiCloud.DotnetBase.App.Adapters.Postgres;

/// <summary>
/// Postgres-backed persistence adapter for notes, over real EF Core migrations. It serves BOTH
/// note ports: the keyed store, and the query side — the latter because it is the store that has
/// the indexes the query side needs.
/// </summary>
/// <param name="context">The relational context.</param>
public sealed class PostgresNoteRepository(NoteDbContext context) : INoteRepository, INoteCatalogue
{
    /// <inheritdoc />
    public async Task<NotePrincipal> Save(NoteRecord record, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(record);

        var principal = new NotePrincipal { Id = Guid.NewGuid().ToString("N"), Record = record };
        context.Notes.Add(principal.ToEntity());
        await context.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
        return principal;
    }

    /// <inheritdoc />
    public async Task<NotePrincipal?> Find(string id, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(id)) throw new ArgumentException("Note id must not be blank.", nameof(id));

        var entity = await context.Notes
            .AsNoTracking()
            .SingleOrDefaultAsync(note => note.Id == id, cancellationToken)
            .ConfigureAwait(false);

        return entity?.ToDomain();
    }

    /// <inheritdoc />
    public async Task<NotePrincipal?> Replace(
        string id,
        NoteRecord record,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(id)) throw new ArgumentException("Note id must not be blank.", nameof(id));
        ArgumentNullException.ThrowIfNull(record);

        // Tracked, unlike Find: this row is about to be written, so the change tracker is the
        // point here rather than an oversight.
        var entity = await context.Notes
            .SingleOrDefaultAsync(note => note.Id == id, cancellationToken)
            .ConfigureAwait(false);

        if (entity is null) return null;

        entity.Title = record.Title;
        entity.Body = record.Body;
        await context.SaveChangesAsync(cancellationToken).ConfigureAwait(false);

        return entity.ToDomain();
    }

    /// <inheritdoc />
    public async Task<bool> Remove(string id, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(id)) throw new ArgumentException("Note id must not be blank.", nameof(id));

        var removed = await context.Notes
            .Where(note => note.Id == id)
            .ExecuteDeleteAsync(cancellationToken)
            .ConfigureAwait(false);

        return removed > 0;
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<NotePrincipal>> All(CancellationToken cancellationToken = default)
    {
        // Ordered by the unique column, so the listing is stable across calls rather than
        // whatever order the planner happens to return.
        var entities = await context.Notes
            .AsNoTracking()
            .OrderBy(note => note.Title)
            .ToListAsync(cancellationToken)
            .ConfigureAwait(false);

        return [.. entities.Select(entity => entity.ToDomain())];
    }

    /// <inheritdoc />
    public async Task<NotePrincipal?> FindByTitle(string title, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(title))
            throw new ArgumentException("Note title must not be blank.", nameof(title));

        var entity = await context.Notes
            .AsNoTracking()
            .SingleOrDefaultAsync(note => note.Title == title, cancellationToken)
            .ConfigureAwait(false);

        return entity?.ToDomain();
    }
}
