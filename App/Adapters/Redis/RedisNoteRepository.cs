using System.Text.Json;
using AtomiCloud.DotnetBase.Lib.Note;
using StackExchange.Redis;

namespace AtomiCloud.DotnetBase.App.Adapters.Redis;

/// <summary>
/// Redis-backed persistence adapter for notes. It implements the KEYED port only.
/// </summary>
/// <remarks>
/// It deliberately does NOT implement <see cref="INoteCatalogue"/>. Enumerating with
/// <c>SCAN note:*</c> is an O(keyspace) walk whose cost is paid by every other tenant of the
/// instance, and there is no secondary index to look a note up by title with. Answering those
/// members with a stub would hide that; not implementing the interface makes it a compile error
/// at the wiring instead.
/// </remarks>
/// <param name="redis">The connection multiplexer.</param>
public class RedisNoteRepository(IConnectionMultiplexer redis) : INoteRepository
{
    private const string KeyPrefix = "note:";

    public async Task<NotePrincipal> Save(NoteRecord record, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var principal = new NotePrincipal { Id = Guid.NewGuid().ToString("N"), Record = record };
        var json = JsonSerializer.Serialize(principal.ToData());
        await redis.GetDatabase().StringSetAsync(KeyPrefix + principal.Id, json);
        cancellationToken.ThrowIfCancellationRequested();
        return principal;
    }

    public async Task<NotePrincipal?> Find(string id, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(id)) throw new ArgumentException("Note id must not be blank.", nameof(id));
        cancellationToken.ThrowIfCancellationRequested();
        var json = await redis.GetDatabase().StringGetAsync(KeyPrefix + id);
        cancellationToken.ThrowIfCancellationRequested();
        if (json.IsNullOrEmpty) return null;
        var data = JsonSerializer.Deserialize<NoteData>(json.ToString());
        return data?.ToDomain();
    }

    public async Task<NotePrincipal?> Replace(
        string id,
        NoteRecord record,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(id)) throw new ArgumentException("Note id must not be blank.", nameof(id));
        ArgumentNullException.ThrowIfNull(record);
        cancellationToken.ThrowIfCancellationRequested();

        // Replace is not an upsert. StringSet with When.Exists does the existence test and the
        // write as ONE command, so a concurrent delete cannot land between a check and a set and
        // leave this method resurrecting a note the caller already removed.
        var principal = new NotePrincipal { Id = id, Record = record };
        var json = JsonSerializer.Serialize(principal.ToData());
        var written = await redis.GetDatabase().StringSetAsync(KeyPrefix + id, json, when: When.Exists);
        cancellationToken.ThrowIfCancellationRequested();

        return written ? principal : null;
    }

    public async Task<bool> Remove(string id, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(id)) throw new ArgumentException("Note id must not be blank.", nameof(id));
        cancellationToken.ThrowIfCancellationRequested();
        var deleted = await redis.GetDatabase().KeyDeleteAsync(KeyPrefix + id);
        cancellationToken.ThrowIfCancellationRequested();
        return deleted;
    }
}
