using Amazon.S3;
using Amazon.S3.Model;
using AtomiCloud.Diene.StandardConfig.Presets;
using AtomiCloud.Diene.StandardConfig.Storage;
using Testcontainers.Minio;
using Testcontainers.PostgreSql;
using Testcontainers.Redis;

namespace AtomiCloud.Diene.StandardConfig.TestHelper.Containers;

/// <summary>Shared knobs for every start helper.</summary>
public class StartOptions
{
    /// <summary>UPPERCASE connection key the emitted block is registered under.</summary>
    public string Key { get; init; } = "MAIN";

    /// <summary>Override the container image.</summary>
    public string? Image { get; init; }
}

/// <summary>Knobs for the Postgres start helper.</summary>
public sealed class StartPostgresOptions : StartOptions
{
    /// <summary>Database name to create.</summary>
    public string Database { get; init; } = "app";

    /// <summary>Role/user name to create.</summary>
    public string Username { get; init; } = "app";

    /// <summary>Password for that role.</summary>
    public string Password { get; init; } = "app-secret";
}

/// <summary>Knobs for the Redis-protocol start helpers (cache and kv).</summary>
public sealed class StartRedisOptions : StartOptions
{
    /// <summary>Logical database index the emitted entry selects.</summary>
    public int Db { get; init; }
}

/// <summary>Knobs for the storage start helper.</summary>
public sealed class StartStorageOptions : StartOptions
{
    /// <summary>Bucket to create inside the container.</summary>
    public string Bucket { get; init; } = "app";

    /// <summary>Region label the emitted entry carries.</summary>
    public string Region { get; init; } = "us-east-1";
}

/// <summary>
/// Per-preset Testcontainers helpers: boot a real dependency and emit the schema-valid,
/// keyed config block that reaches it.
/// </summary>
/// <remarks>
/// This is the whole reason standard-config ships a TestHelper. The container libraries are
/// easy; what every consumer would otherwise hand-roll — per preset, per repository — is the
/// translation from a started container to a valid UPPERCASE-keyed block, and the bucket
/// creation that makes object storage usable at all.
/// </remarks>
public static class StandardConfigContainers
{
    /// <summary>Boots Postgres and emits a valid <c>postgres</c> block.</summary>
    public static async Task<StartedPreset<PostgresBlock, PostgresOption>> StartPostgresAsync(
        StartPostgresOptions? options = null,
        CancellationToken cancellationToken = default)
    {
        options ??= new StartPostgresOptions();

        var container = new PostgreSqlBuilder(options.Image ?? "postgres:16-alpine")
            .WithDatabase(options.Database)
            .WithUsername(options.Username)
            .WithPassword(options.Password)
            .Build();

        await container.StartAsync(cancellationToken).ConfigureAwait(false);

        return new StartedPreset<PostgresBlock, PostgresOption>(container, options.Key, new PostgresOption
        {
            Host = container.Hostname,
            Port = container.GetMappedPublicPort(PostgreSqlBuilder.PostgreSqlPort),
            Database = options.Database,
            Username = options.Username,
            Password = options.Password,
            Ssl = false,
            Pool = new PostgresPoolOption { Min = 0, Max = 10 },
        });
    }

    /// <summary>Boots a Redis-protocol container and emits a valid <c>cache</c> block.</summary>
    public static Task<StartedPreset<CacheBlock, CacheOption>> StartCacheAsync(
        StartRedisOptions? options = null,
        CancellationToken cancellationToken = default) =>
        StartRedisAsync<CacheBlock, CacheOption>(options, cancellationToken);

    /// <summary>Boots a Redis-protocol container and emits a valid <c>kv</c> block.</summary>
    public static Task<StartedPreset<KvBlock, KvOption>> StartKvAsync(
        StartRedisOptions? options = null,
        CancellationToken cancellationToken = default) =>
        StartRedisAsync<KvBlock, KvOption>(options, cancellationToken);

    /// <summary>
    /// Boots MinIO, creates the bucket, and emits a valid <c>storage</c> block.
    /// </summary>
    /// <remarks>
    /// The bucket creation is deliberate: an S3-compatible endpoint with no bucket fails
    /// every write, and "the helper gave me a block that does not work" is precisely the
    /// re-derivation this package exists to prevent.
    /// </remarks>
    public static async Task<StartedPreset<StorageBlock, StorageOption>> StartStorageAsync(
        StartStorageOptions? options = null,
        CancellationToken cancellationToken = default)
    {
        options ??= new StartStorageOptions();

        var container = new MinioBuilder(options.Image ?? "minio/minio:RELEASE.2025-04-22T22-12-26Z")
            .Build();

        await container.StartAsync(cancellationToken).ConfigureAwait(false);

        var entry = new StorageOption
        {
            Endpoint = container.GetConnectionString(),
            Region = options.Region,
            Bucket = options.Bucket,
            AccessKeyId = container.GetAccessKey(),
            SecretAccessKey = container.GetSecretKey(),
            ForcePathStyle = true,
        };

        await CreateBucketAsync(entry, cancellationToken).ConfigureAwait(false);

        return new StartedPreset<StorageBlock, StorageOption>(container, options.Key, entry);
    }

    /// <summary>Creates the entry's bucket if it does not already exist.</summary>
    public static async Task CreateBucketAsync(StorageOption entry, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(entry);

        using var client = new AmazonS3Client(
            entry.AccessKeyId,
            entry.SecretAccessKey,
            S3BlockStorage.ClientConfig(entry));

        try
        {
            await client
                .PutBucketAsync(new PutBucketRequest { BucketName = entry.Bucket }, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (BucketAlreadyOwnedByYouException)
        {
            // Creating a bucket you already own is the success case for this helper.
        }
    }

    private static async Task<StartedPreset<TBlock, TEntry>> StartRedisAsync<TBlock, TEntry>(
        StartRedisOptions? options,
        CancellationToken cancellationToken)
        where TBlock : Dictionary<string, TEntry>, new()
        where TEntry : RedisConnectionOption, new()
    {
        options ??= new StartRedisOptions();

        var container = new RedisBuilder(options.Image ?? "redis:7-alpine")
            .Build();

        await container.StartAsync(cancellationToken).ConfigureAwait(false);

        return new StartedPreset<TBlock, TEntry>(container, options.Key, new TEntry
        {
            Host = container.Hostname,
            Port = container.GetMappedPublicPort(RedisBuilder.RedisPort),
            Password = "",
            Db = options.Db,
            Tls = false,
        });
    }
}
