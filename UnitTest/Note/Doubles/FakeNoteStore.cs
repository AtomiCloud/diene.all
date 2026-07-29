using AtomiCloud.DotnetBase.Lib.Note;

namespace AtomiCloud.DotnetBase.UnitTest.Note.Doubles;

/// <summary>
/// An in-memory store implementing BOTH note ports, used to exercise the domain service without
/// a container.
/// </summary>
/// <remarks>
/// It is a real implementation rather than a mock on purpose: the behaviour the domain service
/// depends on is "a missing row reads back as null" and "replace is not an upsert", and a mock
/// configured per-test would let a test pass against a store that does neither. Title uniqueness
/// is NOT enforced here, so a test can hand the service the state a real race would produce.
/// </remarks>
internal sealed class FakeNoteStore : INoteRepository, INoteCatalogue
{
    private readonly Dictionary<string, NoteRecord> _rows = [];

    private readonly List<string> _minted = [];

    /// <summary>Ids handed out by <see cref="Save"/>, in order.</summary>
    public IReadOnlyList<string> Minted => this._minted;

    /// <summary>Seeds a row directly, bypassing <see cref="Save"/>.</summary>
    /// <param name="id">The identity to seed under.</param>
    /// <param name="record">The content to seed.</param>
    /// <returns>The seeded note.</returns>
    public NotePrincipal Seed(string id, NoteRecord record)
    {
        this._rows[id] = record;
        return new NotePrincipal { Id = id, Record = record };
    }

    /// <inheritdoc />
    public Task<NotePrincipal> Save(NoteRecord record, CancellationToken cancellationToken = default)
    {
        var id = $"note-{this._minted.Count + 1}";
        this._rows[id] = record;
        this._minted.Add(id);
        return Task.FromResult(new NotePrincipal { Id = id, Record = record });
    }

    /// <inheritdoc />
    public Task<NotePrincipal?> Find(string id, CancellationToken cancellationToken = default) =>
        Task.FromResult(this._rows.TryGetValue(id, out var record)
            ? new NotePrincipal { Id = id, Record = record }
            : null);

    /// <inheritdoc />
    public Task<NotePrincipal?> Replace(string id, NoteRecord record, CancellationToken cancellationToken = default)
    {
        if (!this._rows.ContainsKey(id)) return Task.FromResult<NotePrincipal?>(null);
        this._rows[id] = record;
        return Task.FromResult<NotePrincipal?>(new NotePrincipal { Id = id, Record = record });
    }

    /// <inheritdoc />
    public Task<bool> Remove(string id, CancellationToken cancellationToken = default) =>
        Task.FromResult(this._rows.Remove(id));

    /// <inheritdoc />
    public Task<IReadOnlyList<NotePrincipal>> All(CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<NotePrincipal>>(
        [
            .. this._rows
                .OrderBy(row => row.Value.Title, StringComparer.Ordinal)
                .Select(row => new NotePrincipal { Id = row.Key, Record = row.Value }),
        ]);

    /// <inheritdoc />
    public Task<NotePrincipal?> FindByTitle(string title, CancellationToken cancellationToken = default)
    {
        var match = this._rows
            .Where(row => string.Equals(row.Value.Title, title, StringComparison.Ordinal))
            .Select(row => new NotePrincipal { Id = row.Key, Record = row.Value })
            .FirstOrDefault();

        return Task.FromResult(match);
    }
}
