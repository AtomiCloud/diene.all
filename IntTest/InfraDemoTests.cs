using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.IntTest;

/// <summary>
/// The dogfood: the demo's real infra wiring, driven through the real config path, against
/// real dependencies.
/// </summary>
/// <remarks>
/// Nothing here asserts on a preset's SHAPE — the unit tier owns that. What this tier proves
/// is the part a schema cannot: that a block which validates also CONNECTS.
/// </remarks>
public class InfraDemoTests : IAsyncLifetime
{
    private readonly InfraFixture infra = new();

    /// <inheritdoc />
    public ValueTask InitializeAsync() => infra.InitializeAsync();

    /// <inheritdoc />
    public ValueTask DisposeAsync() => infra.DisposeAsync();

    private IConfiguration Configuration() =>
        new ConfigurationBuilder().AddInMemoryCollection(infra.ConfigurationValues()).Build();

    [Fact]
    public async Task It_should_reach_every_dependency_its_presets_describe()
    {
        using var provider = ConfigComposition.Provider(Configuration());

        var result = await InfraDemo.RunAsync(provider, cancellationToken: TestContext.Current.CancellationToken);

        result.IsSuccess(out var lines).Should().BeTrue(result.FailureOrDefault()?.ToString());
        lines.Should().HaveCount(4);
        lines![0].Should().StartWith("postgres[MAIN]").And.Contain("select 1 => 1");
        lines[1].Should().StartWith("cache[MAIN]").And.Contain("ping");
        lines[2].Should().StartWith("kv[MAIN]").And.Contain("ping");
        lines[3].Should().StartWith("storage[MAIN]").And.Contain(InfraDemo.ObjectKey);
    }

    [Fact]
    public async Task It_should_open_the_database_the_postgres_block_names()
    {
        var result = await InfraDemo.InitialiseDatabaseAsync(
            infra.Postgres.Entry,
            TestContext.Current.CancellationToken);

        result.IsSuccess(out var detail).Should().BeTrue();
        detail.Should().Contain("connected to app");
    }

    [Fact]
    public async Task It_should_type_a_db_init_failure_rather_than_throw()
    {
        // The whole reason db-init is Result-typed: an unreachable database is an ordinary
        // startup outcome a service has to report, not an exception escaping the composition
        // root.
        var unreachable = new PostgresOption
        {
            Host = "127.0.0.1",
            Port = 1,
            Database = "app",
            Username = "app",
            Password = "nope",
            Ssl = false,
            Pool = new PostgresPoolOption { Min = 0, Max = 1 },
        };

        var result = await InfraDemo.InitialiseDatabaseAsync(unreachable, TestContext.Current.CancellationToken);

        result.IsFailure(out var error).Should().BeTrue();
        error!.Fault.Should().Be(InfraFault.Postgres);
        error.Connection.Should().Be("app");
        error.ToString().Should().StartWith("Postgres[app]:");
    }

    [Fact]
    public async Task It_should_report_which_dependency_failed()
    {
        var values = new Dictionary<string, string?>(infra.ConfigurationValues(), StringComparer.Ordinal)
        {
            ["storage:MAIN:bucket"] = "does-not-exist",
        };
        using var provider = ConfigComposition.Provider(
            new ConfigurationBuilder().AddInMemoryCollection(values).Build());

        var result = await InfraDemo.RunAsync(provider, cancellationToken: TestContext.Current.CancellationToken);

        result.IsFailure(out var error).Should().BeTrue();
        error!.Fault.Should().Be(InfraFault.Storage);
        error.Connection.Should().Be("does-not-exist");
    }

    [Fact]
    public void It_should_build_a_connection_string_from_the_block()
    {
        var connectionString = InfraDemo.ConnectionString(infra.Postgres.Entry);

        connectionString.Should().Contain("Database=app").And.Contain("SSL Mode=Disable");
    }

    [Fact]
    public void It_should_require_tls_when_the_block_asks_for_it()
    {
        var entry = infra.Postgres.Entry;
        var secured = new PostgresOption
        {
            Host = entry.Host,
            Port = entry.Port,
            Database = entry.Database,
            Username = entry.Username,
            Password = entry.Password,
            Ssl = true,
            Pool = entry.Pool,
        };

        InfraDemo.ConnectionString(secured).Should().Contain("SSL Mode=Require");
    }

    [Fact]
    public void It_should_carry_a_redis_password_only_when_one_is_set()
    {
        InfraDemo.RedisConfiguration(infra.Cache.Entry).Password.Should().BeNull();

        var secured = new CacheOption { Host = "h", Port = 6379, Password = "secret", Db = 0, Tls = false };
        InfraDemo.RedisConfiguration(secured).Password.Should().Be("secret");
    }

    [Fact]
    public void It_should_select_the_database_the_kv_block_names() =>
        InfraDemo.RedisConfiguration(infra.Kv.Entry).DefaultDatabase.Should().Be(infra.Kv.Entry.Db);

    [Fact]
    public void It_should_reject_null_arguments()
    {
        var connectionString = () => InfraDemo.ConnectionString(null!);
        connectionString.Should().Throw<ArgumentNullException>();

        var redis = () => InfraDemo.RedisConfiguration(null!);
        redis.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task It_should_reject_a_null_provider()
    {
        var run = async () => await InfraDemo.RunAsync(null!, cancellationToken: TestContext.Current.CancellationToken);
        await run.Should().ThrowAsync<ArgumentNullException>();
    }
}
