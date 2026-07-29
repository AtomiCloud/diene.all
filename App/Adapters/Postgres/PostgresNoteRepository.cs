using AtomiCloud.DotnetBase.Lib.Note;
using Microsoft.EntityFrameworkCore;

namespace AtomiCloud.DotnetBase.App.Adapters.Postgres;

/// <summary>Postgres-backed persistence adapter for notes, over real EF Core migrations.</summary>
/// <param name="context">The relational context.</param>
public sealed class PostgresNoteRepository(NoteDbContext context) : INoteRepository
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

    /// <summary>Reads a note by its unique title.</summary>
    /// <param name="title">The title to look for.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The note, or <see langword="null"/> when no note carries that title.</returns>
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
