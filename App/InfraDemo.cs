using Amazon.S3;
using System.Globalization;
using System.Text;
using AtomiCloud.Diene.StandardConfig.Presets;
using AtomiCloud.Diene.StandardConfig.Storage;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Npgsql;
using StackExchange.Redis;

namespace AtomiCloud.DotnetBase.App;

/// <summary>Which piece of infrastructure a demo step failed against.</summary>
public enum InfraFault
{
    /// <summary>Opening or querying the Postgres connection failed.</summary>
    Postgres,

    /// <summary>Reaching the ephemeral cache failed.</summary>
    Cache,

    /// <summary>Reaching the persistent kv store failed.</summary>
    Kv,

    /// <summary>An object-storage operation failed.</summary>
    Storage,
}

/// <summary>
/// A typed infrastructure-initialization failure.
/// </summary>
/// <remarks>
/// Deliberately local to the consumer. The problems lib owns catalogued, RFC 9457 problems
/// and sits ABOVE standard-config in the DAG, so a service — not this library — is where a
/// db-init failure becomes a catalogued Problem. Until that lib publishes, this is the shape
/// a consumer maps from.
/// </remarks>
public sealed record InfraError(InfraFault Fault, string Connection, string Detail)
{
    /// <inheritdoc />
    public override string ToString() => $"{Fault}[{Connection}]: {Detail}";
}

/// <summary>
/// Exercises the four infra presets against the real dependencies they describe — the
/// dogfood that proves a preset block is not merely well-typed but actually connects.
/// </summary>
public static class InfraDemo
{
    /// <summary>The object key the storage step writes.</summary>
    public const string ObjectKey = "demo/standard-config.txt";

    /// <summary>Runs every step, stopping at the first failure.</summary>
    public static async Task<Result<IReadOnlyList<string>, InfraError>> RunAsync(
        IServiceProvider provider,
        string connection = "MAIN",
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(provider);

        var lines = new List<string>();

        var postgres = await InitialiseDatabaseAsync(Block<PostgresBlock>(provider).Named(connection), cancellationToken)
            .ConfigureAwait(false);
        if (postgres.IsFailure(out var postgresError)) return Fail(postgresError);
        lines.Add($"postgres[{connection}] {postgres.Get()}");

        var cache = await PingRedisAsync(
                InfraFault.Cache,
                connection,
                Block<CacheBlock>(provider).Named(connection),
                cancellationToken)
            .ConfigureAwait(false);
        if (cache.IsFailure(out var cacheError)) return Fail(cacheError);
        lines.Add($"cache[{connection}] {cache.Get()}");

        var kv = await PingRedisAsync(
                InfraFault.Kv,
                connection,
                Block<KvBlock>(provider).Named(connection),
                cancellationToken)
            .ConfigureAwait(false);
        if (kv.IsFailure(out var kvError)) return Fail(kvError);
        lines.Add($"kv[{connection}] {kv.Get()}");

        var storage = await StoreObjectAsync(Block<StorageBlock>(provider).Named(connection), cancellationToken)
            .ConfigureAwait(false);
        if (storage.IsFailure(out var storageError)) return Fail(storageError);
        lines.Add($"storage[{connection}] {storage.Get()}");

        return Result.Ok<IReadOnlyList<string>, InfraError>(lines);
    }

    /// <summary>
    /// The db-init step: open the pooled connection the block describes and prove the server
    /// answers.
    /// </summary>
    public static async Task<Result<string, InfraError>> InitialiseDatabaseAsync(
        PostgresOption entry,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(entry);

        try
        {
            await using var connection = new NpgsqlConnection(ConnectionString(entry));
            await connection.OpenAsync(cancellationToken).ConfigureAwait(false);

            await using var command = new NpgsqlCommand("select 1", connection);
            var answer = await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false);

            return Result.Ok<string, InfraError>(
                string.Create(CultureInfo.InvariantCulture, $"connected to {entry.Database}, select 1 => {answer}"));
        }
        catch (Exception exception) when (exception is NpgsqlException or InvalidOperationException or TimeoutException)
        {
            return Result.Err<string, InfraError>(
                new InfraError(InfraFault.Postgres, entry.Database, exception.Message));
        }
    }

    /// <summary>The connection string the postgres preset block describes.</summary>
    public static string ConnectionString(PostgresOption entry)
    {
        ArgumentNullException.ThrowIfNull(entry);

        return new NpgsqlConnectionStringBuilder
        {
            Host = entry.Host,
            Port = entry.Port,
            Database = entry.Database,
            Username = entry.Username,
            Password = entry.Password,
            SslMode = entry.Ssl ? SslMode.Require : SslMode.Disable,
            MinPoolSize = entry.Pool.Min,
            MaxPoolSize = entry.Pool.Max,
        }.ConnectionString;
    }

    /// <summary>The StackExchange.Redis configuration a Redis-protocol preset entry describes.</summary>
    public static ConfigurationOptions RedisConfiguration(RedisConnectionOption entry)
    {
        ArgumentNullException.ThrowIfNull(entry);

        var options = new ConfigurationOptions
        {
            DefaultDatabase = entry.Db,
            Ssl = entry.Tls,
            AbortOnConnectFail = false,
        };
        options.EndPoints.Add(entry.Host, entry.Port);
        if (!string.IsNullOrEmpty(entry.Password)) options.Password = entry.Password;
        return options;
    }

    private static async Task<Result<string, InfraError>> PingRedisAsync(
        InfraFault fault,
        string connection,
        RedisConnectionOption entry,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var multiplexer = await ConnectionMultiplexer
                .ConnectAsync(RedisConfiguration(entry))
                .WaitAsync(cancellationToken)
                .ConfigureAwait(false);

            var latency = await multiplexer.GetDatabase().PingAsync().WaitAsync(cancellationToken).ConfigureAwait(false);

            return Result.Ok<string, InfraError>(
                string.Create(CultureInfo.InvariantCulture, $"ping answered in under {latency.TotalMilliseconds:F0}ms"));
        }
        catch (Exception exception) when (exception is RedisException or OperationCanceledException or TimeoutException)
        {
            return Result.Err<string, InfraError>(new InfraError(fault, connection, exception.Message));
        }
    }

    /// <summary>
    /// Uploads one object through the block-storage INTERFACE, not the concrete adapter.
    /// </summary>
    /// <remarks>
    /// The client is constructed here and handed to the constructor overload rather than going
    /// through <c>S3BlockStorage.Create</c>, because that is the shape a real service wants:
    /// the AWS client is usually already registered in DI with its own handler and retry
    /// policy, and the adapter should use that one instead of building a second.
    /// </remarks>
    public static async Task<Result<string, InfraError>> StoreObjectAsync(
        StorageOption entry,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(entry);

        using var client = new AmazonS3Client(
            entry.AccessKeyId,
            entry.SecretAccessKey,
            S3BlockStorage.ClientConfig(entry));
        IBlockStorage storage = new S3BlockStorage(client, entry);

        var saved = await storage
            .SaveAsync(
                new SaveInput
                {
                    Key = ObjectKey,
                    Body = Encoding.UTF8.GetBytes("stored through the standard-config storage preset"),
                    ContentType = "text/plain",
                },
                cancellationToken)
            .ConfigureAwait(false);

        return saved.Match(
            stored => Result.Ok<string, InfraError>(
                $"stored {stored.Key} at {stored.Link} (same as GetLink: {stored.Link == storage.GetLink(stored.Key)}), " +
                $"signed {Shorten(storage.GetSignedUrl(stored.Key, new SignedUrlOptions { Method = SignedUrlMethod.Get }))}"),
            error => Result.Err<string, InfraError>(new InfraError(InfraFault.Storage, entry.Bucket, error.ToString())));
    }

    /// <summary>A signed URL is long and mostly signature; the demo prints only its head.</summary>
    private static string Shorten(string url)
    {
        var query = url.IndexOf('?', StringComparison.Ordinal);
        return query < 0 ? url : url[..query] + "?...";
    }

    private static TBlock Block<TBlock>(IServiceProvider provider)
        where TBlock : class =>
        provider.GetRequiredService<IOptions<TBlock>>().Value;

    private static Result<IReadOnlyList<string>, InfraError> Fail(InfraError error) =>
        Result.Err<IReadOnlyList<string>, InfraError>(error);
}
