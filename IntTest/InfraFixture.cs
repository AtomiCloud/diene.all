using AtomiCloud.Diene.StandardConfig.TestHelper.Containers;
using AtomiCloud.Diene.StandardConfig.Storage;

namespace AtomiCloud.DotnetBase.IntTest;

/// <summary>
/// One set of real dependencies for the whole integration tier, booted through the shipped
/// TestHelper glue.
/// </summary>
/// <remarks>
/// The fixture is itself part of the dogfood: if a consumer's integration setup would be
/// awkward with these helpers, it is awkward here first.
/// </remarks>
public sealed class InfraFixture : IAsyncLifetime
{
    private StartedPreset<PostgresBlock, PostgresOption>? _postgres;
    private StartedPreset<CacheBlock, CacheOption>? _cache;
    private StartedPreset<KvBlock, KvOption>? _kv;
    private StartedPreset<StorageBlock, StorageOption>? _storage;

    /// <summary>The started Postgres block.</summary>
    public StartedPreset<PostgresBlock, PostgresOption> Postgres => _postgres!;

    /// <summary>The started cache block.</summary>
    public StartedPreset<CacheBlock, CacheOption> Cache => _cache!;

    /// <summary>The started kv block.</summary>
    public StartedPreset<KvBlock, KvOption> Kv => _kv!;

    /// <summary>The started storage block.</summary>
    public StartedPreset<StorageBlock, StorageOption> Storage => _storage!;

    /// <summary>The flattened configuration every started block contributes.</summary>
    public IReadOnlyDictionary<string, string?> ConfigurationValues()
    {
        var values = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (var pair in Postgres.ConfigurationValues(PostgresOption.Key)) values[pair.Key] = pair.Value;
        foreach (var pair in Cache.ConfigurationValues(CacheOption.Key)) values[pair.Key] = pair.Value;
        foreach (var pair in Kv.ConfigurationValues(KvOption.Key)) values[pair.Key] = pair.Value;
        foreach (var pair in Storage.ConfigurationValues(StorageOption.Key)) values[pair.Key] = pair.Value;
        return values;
    }

    /// <inheritdoc />
    public async ValueTask InitializeAsync()
    {
        _postgres = await StandardConfigContainers.StartPostgresAsync();
        _cache = await StandardConfigContainers.StartCacheAsync();
        _kv = await StandardConfigContainers.StartKvAsync();
        _storage = await StandardConfigContainers.StartStorageAsync();
    }

    /// <inheritdoc />
    public async ValueTask DisposeAsync()
    {
        if (_storage is not null) await _storage.DisposeAsync();
        if (_kv is not null) await _kv.DisposeAsync();
        if (_cache is not null) await _cache.DisposeAsync();
        if (_postgres is not null) await _postgres.DisposeAsync();
    }
}

