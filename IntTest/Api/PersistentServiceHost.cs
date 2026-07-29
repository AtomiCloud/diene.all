using AtomiCloud.Diene.StandardConfig.Presets;
using AtomiCloud.Diene.StandardConfig.TestHelper.Containers;
using AtomiCloud.DotnetBase.App.Adapters.Postgres;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.IntTest.Api;

/// <summary>
/// The service host with REAL infrastructure behind it: a Postgres container for the note store
/// and a cache container for anything that reaches the multiplexer. Only the cases that must
/// cross a real driver belong here.
/// </summary>
/// <remarks>
/// Schema is provisioned by the SAME path production uses — <c>Database.MigrateAsync</c> — and
/// deliberately NOT by <c>EnsureCreated</c>. <see cref="NoteDbContext"/> says so in its own doc
/// comment, and the reason matters: <c>EnsureCreated</c> builds a schema from the current model
/// and would make this suite pass against a service whose migrations do not exist or do not
/// match. That is precisely the failure being guarded, so a store with no migrations FAILS here,
/// loudly, naming the defect.
/// </remarks>
public sealed class PersistentServiceHost : ServiceHost, IAsyncLifetime
{
    private StartedPreset<PostgresBlock, PostgresOption>? _postgres;
    private StartedPreset<CacheBlock, CacheOption>? _cache;

    /// <summary>The migrations that were applied, so a test can report what it ran against.</summary>
    public IReadOnlyList<string> AppliedMigrations { get; private set; } = [];

    /// <summary>Starts the containers, then applies real migrations.</summary>
    /// <returns>A task that completes when the host is ready to serve.</returns>
    public async ValueTask InitializeAsync()
    {
        this._postgres = await StandardConfigContainers
            .StartPostgresAsync(new StartPostgresOptions { Key = "MAIN" })
            .ConfigureAwait(false);

        this._cache = await StandardConfigContainers
            .StartCacheAsync(new StartRedisOptions { Key = "MAIN" })
            .ConfigureAwait(false);

        // Touching Services builds the host, which is why the containers must already be up:
        // ConfigureWebHost reads their connection details.
        using var scope = this.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<NoteDbContext>();

        var pending = (await context.Database.GetPendingMigrationsAsync().ConfigureAwait(false)).ToArray();
        if (pending.Length == 0)
        {
            throw new InvalidOperationException(
                "No EF Core migrations were discovered, so the 'notes' table cannot be created and " +
                "this suite has nothing to read or write. This is a defect in the service, not in " +
                "the test: App/Adapters/Postgres has no Migrations directory, which also means " +
                "db-init's migrate step applies nothing and its seed step then queries a table " +
                "that does not exist. Generate the initial migration with: dotnet ef migrations " +
                "add InitialCreate --project App/App.csproj --output-dir Adapters/Postgres/Migrations. " +
                "EnsureCreated is deliberately NOT used as a workaround here — it would hide exactly " +
                "this.");
        }

        await context.Database.MigrateAsync().ConfigureAwait(false);
        this.AppliedMigrations = pending;
    }

    /// <inheritdoc />
    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync().ConfigureAwait(false);
        if (this._cache is not null) await this._cache.DisposeAsync().ConfigureAwait(false);
        if (this._postgres is not null) await this._postgres.DisposeAsync().ConfigureAwait(false);
        GC.SuppressFinalize(this);
    }

    /// <summary>Opens a context against the same database the host serves from.</summary>
    /// <returns>A scope owning the context; dispose it.</returns>
    public AsyncServiceScope Scope() => this.Services.CreateAsyncScope();

    /// <inheritdoc />
    protected override IEnumerable<KeyValuePair<string, string?>> Settings()
    {
        var values = new List<KeyValuePair<string, string?>>(base.Settings());
        Merge(values, this._postgres?.ConfigurationValues(PostgresOption.Key));
        Merge(values, this._cache?.ConfigurationValues(CacheOption.Key));
        return values;
    }

    private static void Merge(
        List<KeyValuePair<string, string?>> into,
        IReadOnlyDictionary<string, string?>? preset)
    {
        if (preset is null) return;
        into.AddRange(preset);
    }
}
