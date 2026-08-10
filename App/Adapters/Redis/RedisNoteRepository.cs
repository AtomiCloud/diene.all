using System.Text.Json;
using AtomiCloud.Diene.Note;
using StackExchange.Redis;

namespace AtomiCloud.DotnetBase.App.Adapters.Redis;

/// <summary>Redis-backed persistence adapter for notes.</summary>
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
}
