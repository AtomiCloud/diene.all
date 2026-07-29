using Amazon.S3;
using Amazon.S3.Model;
using AtomiCloud.Diene.Config;
using AtomiCloud.Diene.CoreUtils;
using AtomiCloud.Diene.StandardConfig.Presets;
using AtomiCloud.Diene.StandardConfig.Storage;
using AtomiCloud.DotnetBase.App.Adapters.Postgres;
using AtomiCloud.DotnetBase.App.Options;
using AtomiCloud.DotnetBase.App.StartUp.Registration;
using AtomiCloud.DotnetBase.Lib.Note;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using StackExchange.Redis;

namespace AtomiCloud.DotnetBase.App.StartUp;

/// <summary>
/// The one-shot initialisation path: check every dependency is reachable, create the bucket,
/// apply real EF Core migrations, and seed preset data if it is not already there.
/// </summary>
/// <remarks>
/// This runs as its own hook-scoped Job BEFORE the rollout, never as part of the serving
/// deployment. That separation is what lets the Deployment do an ordinary rolling update while
/// a migration is in flight, instead of the Job's presence recreating the whole app.
/// </remarks>
public static class DbInit
{
    /// <summary>Exit code when every enabled step completed.</summary>
    public const int Success = 0;

    /// <summary>Exit code when a dependency never became reachable, or a step failed.</summary>
    public const int Failure = 1;

    /// <summary>Composes the initialisation host. It shares the server's configuration layers.</summary>
    /// <param name="args">The process arguments.</param>
    /// <returns>A built, unstarted host.</returns>
    public static IHost Build(string[] args)
    {
        var builder = Host.CreateApplicationBuilder(args);

        builder.Configuration.AddServiceConfiguration(landscape: string.Empty);
        builder.Services.AddServiceOptions();
        builder.Services.AddServicePersistence();
        builder.Services.AddServiceCache();

        return builder.Build();
    }

    /// <summary>Runs the initialisation path and returns a process exit code.</summary>
    /// <param name="args">The process arguments.</param>
    /// <returns>The process exit code.</returns>
    public static async Task<int> RunAsync(string[] args)
    {
        using var host = Build(args);
        using var scope = host.Services.CreateScope();
        var services = scope.ServiceProvider;

        var logger = services.GetRequiredService<ILoggerFactory>().CreateLogger(nameof(DbInit));
        var options = services.GetRequiredService<IOptions<DbInitOption>>().Value;

        var window = Duration(options.ReachabilityWindow);
        var timeout = Duration(options.ReachabilityTimeout);

        try
        {
            if (options.CheckReachability &&
                !await ReachableAsync(services, logger, window, timeout).ConfigureAwait(false))
                return Failure;

            if (options.CreateBucket) await CreateBucketAsync(services, logger).ConfigureAwait(false);
            if (options.Migrate) await MigrateAsync(services, logger).ConfigureAwait(false);
            if (options.Seed) await SeedAsync(services, logger).ConfigureAwait(false);
        }
        catch (Exception failure) when (failure is not OperationCanceledException)
        {
            logger.LogError(failure, "db-init failed");
            return Failure;
        }

        logger.LogInformation("db-init complete");
        return Success;
    }

    private static async Task<bool> ReachableAsync(
        IServiceProvider services,
        ILogger logger,
        TimeSpan window,
        TimeSpan timeout)
    {
        var checks = new (string Name, Func<CancellationToken, Task> Probe)[]
        {
            ("postgres", token => services.GetRequiredService<NoteDbContext>().Database.OpenConnectionAsync(token)),
            ("cache", _ => services.GetRequiredService<IConnectionMultiplexer>().GetDatabase().PingAsync()),
            ("storage", token => StorageReachableAsync(services, token)),
        };

        foreach (var (name, probe) in checks)
        {
            if (await RetryAsync(name, probe, logger, window, timeout).ConfigureAwait(false)) continue;
            logger.LogError("dependency {Dependency} never became reachable within {Window}", name, window);
            return false;
        }

        return true;
    }

    private static async Task<bool> RetryAsync(
        string name,
        Func<CancellationToken, Task> probe,
        ILogger logger,
        TimeSpan window,
        TimeSpan timeout)
    {
        var deadline = DateTimeOffset.UtcNow + window;
        var delay = TimeSpan.FromSeconds(1);

        while (true)
        {
            try
            {
                using var attempt = new CancellationTokenSource(timeout);
                await probe(attempt.Token).ConfigureAwait(false);
                logger.LogInformation("dependency {Dependency} is reachable", name);
                return true;
            }
            catch (Exception failure) when (failure is not OperationCanceledException || DateTimeOffset.UtcNow < deadline)
            {
                if (DateTimeOffset.UtcNow >= deadline) return false;
                logger.LogWarning("dependency {Dependency} not reachable yet: {Reason}", name, failure.Message);
                await Task.Delay(delay).ConfigureAwait(false);
                delay = TimeSpan.FromSeconds(Math.Min(delay.TotalSeconds * 2, 15));
            }
        }
    }

    private static async Task StorageReachableAsync(IServiceProvider services, CancellationToken cancellationToken)
    {
        var storage = services.GetRequiredService<IOptions<StorageBlock>>().Value
            .Named(DomainRegistration.PrimaryConnection);

        using var client = StorageClient(storage);
        await client.ListBucketsAsync(cancellationToken).ConfigureAwait(false);
    }

    private static async Task CreateBucketAsync(IServiceProvider services, ILogger logger)
    {
        var storage = services.GetRequiredService<IOptions<StorageBlock>>().Value
            .Named(DomainRegistration.PrimaryConnection);

        using var client = StorageClient(storage);
        var buckets = await client.ListBucketsAsync().ConfigureAwait(false);

        if (buckets.Buckets.Any(bucket => bucket.BucketName == storage.Bucket))
        {
            logger.LogInformation("bucket {Bucket} already exists", storage.Bucket);
            return;
        }

        await client.PutBucketAsync(new PutBucketRequest { BucketName = storage.Bucket }).ConfigureAwait(false);
        logger.LogInformation("bucket {Bucket} created", storage.Bucket);
    }

    private static async Task MigrateAsync(IServiceProvider services, ILogger logger)
    {
        var context = services.GetRequiredService<NoteDbContext>();
        var pending = (await context.Database.GetPendingMigrationsAsync().ConfigureAwait(false)).ToArray();

        if (pending.Length == 0)
        {
            logger.LogInformation("no pending migrations");
            return;
        }

        logger.LogInformation("applying {Count} migration(s): {Migrations}", pending.Length, string.Join(", ", pending));
        await context.Database.MigrateAsync().ConfigureAwait(false);
    }

    private static async Task SeedAsync(IServiceProvider services, ILogger logger)
    {
        var context = services.GetRequiredService<NoteDbContext>();

        // Seed-if-not-exists, keyed on the unique title, so a re-run is a no-op rather than a
        // duplicate-key failure. Re-running db-init is normal: it happens on every upgrade.
        foreach (var record in Preset)
        {
            if (await context.Notes.AnyAsync(note => note.Title == record.Title).ConfigureAwait(false)) continue;

            context.Notes.Add(new NotePrincipal { Id = Guid.NewGuid().ToString("N"), Record = record }.ToEntity());
            logger.LogInformation("seeding note {Title}", record.Title);
        }

        await context.SaveChangesAsync().ConfigureAwait(false);
    }

    private static IAmazonS3 StorageClient(StorageOption option) => new AmazonS3Client(
        option.AccessKeyId,
        option.SecretAccessKey,
        S3BlockStorage.ClientConfig(option));

    private static TimeSpan Duration(string value) => Wire
        .ParseDuration(value)
        .Match(
            parsed => parsed,
            error => throw new InvalidOperationException($"configuration block 'db_init' is invalid: {error}"));

    // ── Preset data (illustrative sample) — replace with your domain's ──
    private static IReadOnlyList<NoteRecord> Preset =>
    [
        new() { Title = "Welcome", Body = "The first note, seeded by db-init." },
    ];
    // ── End preset data ──
}
