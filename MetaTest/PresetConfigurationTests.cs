using AtomiCloud.Diene.StandardConfig.TestHelper.Containers;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.MetaTest;

/// <summary>
/// Fixture invariants for the flattener: what it emits must be readable by the real
/// configuration binder, or it is a convenience that lies.
/// </summary>
public class PresetConfigurationTests
{
    private static PostgresOption Entry() => new()
    {
        Host = "db.internal",
        Port = 5432,
        Database = "app",
        Username = "app",
        Password = "",
        Ssl = true,
        Pool = new PostgresPoolOption { Min = 1, Max = 9 },
    };

    [Fact]
    public void It_should_flatten_nested_properties_onto_delimited_keys()
    {
        var values = PresetConfiguration.Flatten(PostgresOption.Key, "MAIN", Entry());

        values["postgres:MAIN:host"].Should().Be("db.internal");
        values["postgres:MAIN:port"].Should().Be("5432");
        values["postgres:MAIN:pool:min"].Should().Be("1");
        values["postgres:MAIN:pool:max"].Should().Be("9");
    }

    [Fact]
    public void It_should_spell_booleans_the_way_a_yaml_layer_would() =>
        PresetConfiguration.Flatten(PostgresOption.Key, "MAIN", Entry())["postgres:MAIN:ssl"].Should().Be("true");

    [Fact]
    public void It_should_keep_a_blank_secret_as_a_present_key()
    {
        var values = PresetConfiguration.Flatten(PostgresOption.Key, "MAIN", Entry());

        values.Should().ContainKey("postgres:MAIN:password");
        values["postgres:MAIN:password"].Should().BeEmpty();
    }

    [Fact]
    public void It_should_emit_a_null_for_an_absent_nested_object()
    {
        var entry = Entry();
        entry.Pool = null!;

        PresetConfiguration.Flatten(PostgresOption.Key, "MAIN", entry)["postgres:MAIN:pool"].Should().BeNull();
    }

    [Fact]
    public void It_should_flatten_every_named_connection_in_a_block()
    {
        var block = new PostgresBlock { ["MAIN"] = Entry(), ["REPLICA"] = Entry() };

        var values = PresetConfiguration.FlattenBlock(PostgresOption.Key, block);

        values.Should().ContainKey("postgres:MAIN:host").And.ContainKey("postgres:REPLICA:host");
    }

    [Fact]
    public void It_should_produce_keys_the_real_binder_reads_back()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(PresetConfiguration.Flatten(PostgresOption.Key, "MAIN", Entry()))
            .Build();

        var bound = configuration.GetSection("postgres").Get<PostgresBlock>();

        bound.Should().NotBeNull();
        bound!.Named("MAIN").Pool.Max.Should().Be(9);
        bound.Named("MAIN").Ssl.Should().BeTrue();
    }

    [Theory]
    [InlineData("", "MAIN")]
    [InlineData("Postgres", "")]
    public void It_should_reject_a_blank_block_key_or_name(string block, string name)
    {
        var flatten = () => PresetConfiguration.Flatten(block, name, Entry());
        flatten.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_reject_a_null_entry()
    {
        var flatten = () => PresetConfiguration.Flatten<PostgresOption>(PostgresOption.Key, "MAIN", null!);
        flatten.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_blank_block_key_when_flattening_a_block()
    {
        var flatten = () => PresetConfiguration.FlattenBlock("  ", new PostgresBlock());
        flatten.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_reject_a_null_block()
    {
        var flatten = () => PresetConfiguration.FlattenBlock<PostgresOption>(PostgresOption.Key, null!);
        flatten.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_render_an_enum_by_name()
    {
        var holder = new EnumHolder();

        holder.Mode.Should().Be(Mode.Second).And.NotBe(Mode.First);
        PresetConfiguration.Flatten("Demo", "MAIN", holder)["demo:MAIN:mode"].Should().Be("Second");
    }

    [Fact]
    public void It_should_skip_indexer_properties()
    {
        var holder = new IndexerHolder();

        // The indexer is real and reachable; the flattener still must not walk into it.
        holder.Name.Should().Be("held");
        holder[7].Should().Be("7");
        PresetConfiguration.Flatten("Demo", "MAIN", holder).Keys.Should().BeEquivalentTo(["demo:MAIN:name"]);
    }

    private enum Mode
    {
        First,
        Second,
    }

    private sealed class EnumHolder
    {
        public Mode Mode { get; } = Mode.Second;
    }

    private sealed class IndexerHolder
    {
        public string Name { get; } = "held";

        public string this[int index] => index.ToString(System.Globalization.CultureInfo.InvariantCulture);
    }
}
