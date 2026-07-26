using AtomiCloud.Diene.StandardConfig.TestHelper.Containers;

namespace AtomiCloud.DotnetBase.MetaTest;

/// <summary>
/// The glue's own contract: every start helper must emit a block that its preset validator
/// accepts, keyed under the name the caller asked for.
/// </summary>
/// <remarks>
/// A helper that boots a container but emits an invalid or wrongly-keyed block has moved the
/// consumer's problem rather than solved it, and the failure would surface in the consumer's
/// suite rather than here.
/// </remarks>
[Collection("containers")]
public class ContainerGlueTests
{
    [Fact]
    public async Task It_should_emit_a_valid_postgres_block()
    {
        var token = TestContext.Current.CancellationToken;
        await using var started = await StandardConfigContainers.StartPostgresAsync(cancellationToken: token);

        started.Key.Should().Be("MAIN");
        started.Block.ShouldAsPresetBlock().HaveConnection("MAIN").Which.Port.Should().Be(started.Entry.Port);
        started.Block.ShouldAsPresetBlock().BeValidAgainst(new PostgresBlockValidator());
        started.Entry.Pool.Max.Should().Be(10);
    }

    [Fact]
    public async Task It_should_honour_an_explicit_postgres_identity_and_key()
    {
        var token = TestContext.Current.CancellationToken;
        await using var started = await StandardConfigContainers.StartPostgresAsync(
            new StartPostgresOptions
            {
                Key = "REPLICA",
                Database = "orders",
                Username = "reader",
                Password = "reader-secret",
            },
            token);

        started.Key.Should().Be("REPLICA");
        started.Entry.Database.Should().Be("orders");
        started.Entry.Username.Should().Be("reader");
        started.Block.ShouldAsPresetBlock().HaveConnection("REPLICA");
    }

    [Fact]
    public async Task It_should_emit_a_valid_cache_block_from_a_pinned_image()
    {
        // Pinning the image is the knob a consumer reaches for when its landscape runs a
        // specific Redis-protocol build rather than the helper default.
        var token = TestContext.Current.CancellationToken;
        await using var started = await StandardConfigContainers.StartCacheAsync(
            new StartRedisOptions { Image = "redis:7.4-alpine" },
            token);

        started.Block.ShouldAsPresetBlock().BeValidAgainst(new CacheBlockValidator());
        started.Entry.Tls.Should().BeFalse();
    }

    [Fact]
    public async Task It_should_emit_a_valid_kv_block_on_a_chosen_database()
    {
        var token = TestContext.Current.CancellationToken;
        await using var started = await StandardConfigContainers.StartKvAsync(
            new StartRedisOptions { Key = "SESSIONS", Db = 3 },
            token);

        started.Key.Should().Be("SESSIONS");
        started.Entry.Db.Should().Be(3);
        started.Block.ShouldAsPresetBlock().BeValidAgainst(new KvBlockValidator());
    }

    [Fact]
    public async Task It_should_emit_a_valid_storage_block_whose_bucket_already_exists()
    {
        var token = TestContext.Current.CancellationToken;
        await using var started = await StandardConfigContainers.StartStorageAsync(
            new StartStorageOptions { Bucket = "uploads" },
            token);

        started.Entry.Bucket.Should().Be("uploads");
        started.Entry.ForcePathStyle.Should().BeTrue();
        started.Block.ShouldAsPresetBlock().BeValidAgainst(new StorageBlockValidator());

        // Creating the same bucket twice is the helper's success case, not a failure.
        var again = async () => await StandardConfigContainers.CreateBucketAsync(started.Entry, token);
        await again.Should().NotThrowAsync();
    }

    [Fact]
    public async Task It_should_reject_a_null_entry_when_creating_a_bucket()
    {
        var create = async () => await StandardConfigContainers.CreateBucketAsync(
            null!,
            TestContext.Current.CancellationToken);

        await create.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task It_should_flatten_a_block_into_configuration_keys()
    {
        var token = TestContext.Current.CancellationToken;
        await using var started = await StandardConfigContainers.StartPostgresAsync(cancellationToken: token);

        var values = started.ConfigurationValues(PostgresOption.Key);

        values.Should().ContainKey("postgres:MAIN:host");
        values.Should().ContainKey("postgres:MAIN:pool:max");
        values["postgres:MAIN:ssl"].Should().Be("false");
        values["postgres:MAIN:database"].Should().Be("app");
    }
}
