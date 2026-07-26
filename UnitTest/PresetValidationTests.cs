using FluentValidation;

namespace AtomiCloud.DotnetBase.UnitTest;

public class PresetValidationTests
{
    private static PostgresOption Postgres() => new()
    {
        Host = "localhost",
        Port = 5432,
        Database = "app",
        Username = "app",
        Password = "",
        Ssl = false,
        Pool = new PostgresPoolOption { Min = 0, Max = 10 },
    };

    private static CacheOption Cache() => new() { Host = "localhost", Port = 6379, Password = "", Db = 0, Tls = false };

    private static KvOption Kv() => new() { Host = "localhost", Port = 6379, Password = "", Db = 0, Tls = false };

    private static StorageOption Storage() => new()
    {
        Endpoint = "http://localhost:9000",
        Region = "us-east-1",
        Bucket = "app",
        AccessKeyId = "",
        SecretAccessKey = "",
        ForcePathStyle = true,
    };

    private static TBlock Block<TBlock, TEntry>(TEntry entry, string name = "main")
        where TBlock : Dictionary<string, TEntry>, new() =>
        new() { [name] = entry };

    private static void ShouldAccept<TBlock>(IValidator<TBlock> validator, TBlock block) =>
        validator.Validate(block).IsValid.Should().BeTrue();

    private static void ShouldReject<TBlock>(
        IValidator<TBlock> validator,
        TBlock block,
        string expected)
    {
        var result = validator.Validate(block);

        result.IsValid.Should().BeFalse();
        result.Errors.Select(failure => failure.ErrorMessage).Should().ContainMatch($"*{expected}*");
    }

    // ── the four presets accept a well-formed block ─────────────────────────────────────

    [Fact]
    public void It_should_accept_a_valid_postgres_block() =>
        ShouldAccept(new PostgresBlockValidator(), Block<PostgresBlock, PostgresOption>(Postgres()));

    [Fact]
    public void It_should_accept_a_valid_cache_block() => ShouldAccept(new CacheBlockValidator(), Block<CacheBlock, CacheOption>(Cache()));

    [Fact]
    public void It_should_accept_a_valid_kv_block() => ShouldAccept(new KvBlockValidator(), Block<KvBlock, KvOption>(Kv()));

    [Fact]
    public void It_should_accept_a_valid_storage_block() =>
        ShouldAccept(new StorageBlockValidator(), Block<StorageBlock, StorageOption>(Storage()));

    // ── secrets are blank in yaml, so a blank secret must NOT be a validation failure ────

    [Fact]
    public void It_should_accept_a_blank_postgres_password() =>
        ShouldAccept(new PostgresBlockValidator(), Block<PostgresBlock, PostgresOption>(Postgres()));

    [Fact]
    public void It_should_accept_blank_storage_credentials() =>
        ShouldAccept(new StorageBlockValidator(), Block<StorageBlock, StorageOption>(Storage()));

    // ── the shared key rule ─────────────────────────────────────────────────────────────

    [Fact]
    public void It_should_reject_a_pool_name_with_punctuation() =>
        ShouldReject(new CacheBlockValidator(), Block<CacheBlock, CacheOption>(Cache(), "my@pool"), "UPPERCASE");

    [Fact]
    public void It_should_reject_a_pool_name_starting_with_a_digit() =>
        ShouldReject(new PostgresBlockValidator(), Block<PostgresBlock, PostgresOption>(Postgres(), "2main"), "UPPERCASE");

    [Fact]
    public void It_should_accept_several_named_connections()
    {
        var block = Block<PostgresBlock, PostgresOption>(Postgres());
        block["replica"] = Postgres();

        ShouldAccept(new PostgresBlockValidator(), block);
    }

    // ── per-entry rules ─────────────────────────────────────────────────────────────────

    [Fact]
    public void It_should_reject_a_postgres_entry_without_a_host()
    {
        var entry = Postgres();
        entry.Host = "";
        ShouldReject(new PostgresBlockValidator(), Block<PostgresBlock, PostgresOption>(entry), "Host");
    }

    [Theory]
    [InlineData(0)]
    [InlineData(70000)]
    public void It_should_reject_a_postgres_port_outside_the_tcp_range(int port)
    {
        var entry = Postgres();
        entry.Port = port;
        ShouldReject(new PostgresBlockValidator(), Block<PostgresBlock, PostgresOption>(entry), "Port");
    }

    [Fact]
    public void It_should_reject_a_postgres_entry_without_a_database()
    {
        var entry = Postgres();
        entry.Database = "";
        ShouldReject(new PostgresBlockValidator(), Block<PostgresBlock, PostgresOption>(entry), "Database");
    }

    [Fact]
    public void It_should_reject_a_postgres_entry_without_a_username()
    {
        var entry = Postgres();
        entry.Username = "";
        ShouldReject(new PostgresBlockValidator(), Block<PostgresBlock, PostgresOption>(entry), "Username");
    }

    [Fact]
    public void It_should_reject_a_negative_pool_minimum()
    {
        var entry = Postgres();
        entry.Pool = new PostgresPoolOption { Min = -1, Max = 10 };
        ShouldReject(new PostgresBlockValidator(), Block<PostgresBlock, PostgresOption>(entry), "Min");
    }

    [Fact]
    public void It_should_reject_a_pool_that_can_hold_no_connections()
    {
        var entry = Postgres();
        entry.Pool = new PostgresPoolOption { Min = 0, Max = 0 };
        ShouldReject(new PostgresBlockValidator(), Block<PostgresBlock, PostgresOption>(entry), "Max");
    }

    [Fact]
    public void It_should_reject_a_pool_whose_maximum_is_below_its_minimum()
    {
        var entry = Postgres();
        entry.Pool = new PostgresPoolOption { Min = 8, Max = 4 };
        ShouldReject(new PostgresBlockValidator(), Block<PostgresBlock, PostgresOption>(entry), "pool.max");
    }

    [Fact]
    public void It_should_reject_a_postgres_entry_without_a_pool()
    {
        var entry = Postgres();
        entry.Pool = null!;
        ShouldReject(new PostgresBlockValidator(), Block<PostgresBlock, PostgresOption>(entry), "Pool");
    }

    [Fact]
    public void It_should_reject_a_cache_entry_without_a_host()
    {
        var entry = Cache();
        entry.Host = "";
        ShouldReject(new CacheBlockValidator(), Block<CacheBlock, CacheOption>(entry), "Host");
    }

    [Fact]
    public void It_should_reject_a_negative_cache_database_index()
    {
        var entry = Cache();
        entry.Db = -1;
        ShouldReject(new CacheBlockValidator(), Block<CacheBlock, CacheOption>(entry), "Db");
    }

    [Fact]
    public void It_should_reject_a_kv_entry_with_an_out_of_range_port()
    {
        var entry = Kv();
        entry.Port = 0;
        ShouldReject(new KvBlockValidator(), Block<KvBlock, KvOption>(entry), "Port");
    }

    [Fact]
    public void It_should_reject_a_storage_entry_without_an_endpoint()
    {
        var entry = Storage();
        entry.Endpoint = "";
        ShouldReject(new StorageBlockValidator(), Block<StorageBlock, StorageOption>(entry), "Endpoint");
    }

    [Fact]
    public void It_should_reject_a_storage_entry_without_a_region()
    {
        var entry = Storage();
        entry.Region = "";
        ShouldReject(new StorageBlockValidator(), Block<StorageBlock, StorageOption>(entry), "Region");
    }

    [Fact]
    public void It_should_reject_a_storage_entry_without_a_bucket()
    {
        var entry = Storage();
        entry.Bucket = "";
        ShouldReject(new StorageBlockValidator(), Block<StorageBlock, StorageOption>(entry), "Bucket");
    }

    // ── the frozen block keys ───────────────────────────────────────────────────────────

    [Fact]
    public void It_should_keep_the_four_frozen_block_keys()
    {
        PostgresOption.Key.Should().Be("Postgres");
        CacheOption.Key.Should().Be("Cache");
        KvOption.Key.Should().Be("Kv");
        StorageOption.Key.Should().Be("Storage");
    }

    [Fact]
    public void It_should_keep_cache_and_kv_as_separate_types_over_one_connection_shape()
    {
        // Identical connection fields, deliberately different durability contracts. Sharing
        // the base type must never let one be substituted for the other.
        typeof(CacheOption).Should().BeDerivedFrom<RedisConnectionOption>();
        typeof(KvOption).Should().BeDerivedFrom<RedisConnectionOption>();
        typeof(CacheOption).Should().NotBeAssignableTo<KvOption>();
        typeof(KvOption).Should().NotBeAssignableTo<CacheOption>();
    }
}
