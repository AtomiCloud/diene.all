using AtomiCloud.Diene.Config;
using AtomiCloud.Diene.StandardConfig.TestHelper;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace AtomiCloud.DotnetBase.IntTest;

/// <summary>
/// The demo consumer's own YAML, resolved through the whole precedence order — the layers a
/// deployed service actually has.
/// </summary>
public class ConfigCompositionTests
{
    [Fact]
    public void It_should_layer_the_base_file_under_the_landscape_overlay()
    {
        var configuration = ConfigComposition.Build(PresetDemo.Landscape, []);
        using var provider = ConfigComposition.Provider(configuration);

        // The overlay names only the kv port, so cache keeps the base value and kv takes the
        // overlay one.
        Block<CacheBlock>(provider).Named("MAIN").Port.Should().Be(6379);
        Block<KvBlock>(provider).Named("MAIN").Port.Should().Be(6381);
    }

    [Fact]
    public void It_should_let_the_environment_override_the_files()
    {
        var configuration = ConfigComposition.Build(
            PresetDemo.Landscape,
            new Dictionary<string, string?>(StringComparer.Ordinal) { ["ATOMI_KV__MAIN__PORT"] = "7000" });
        using var provider = ConfigComposition.Provider(configuration);

        Block<KvBlock>(provider).Named("MAIN").Port.Should().Be(7000);
    }

    [Fact]
    public void It_should_inject_a_secret_declared_blank_in_yaml()
    {
        var blank = ConfigComposition.Build(PresetDemo.Landscape, []);
        using var blankProvider = ConfigComposition.Provider(blank);
        Block<PostgresBlock>(blankProvider).Named("MAIN").Password.Should().BeEmpty();

        var injected = ConfigComposition.Build(
            PresetDemo.Landscape,
            new Dictionary<string, string?>(StringComparer.Ordinal)
            {
                ["ATOMI_POSTGRES__MAIN__PASSWORD"] = "from-the-landscape",
            });
        using var injectedProvider = ConfigComposition.Provider(injected);
        Block<PostgresBlock>(injectedProvider).Named("MAIN").Password.Should().Be("from-the-landscape");
    }

    [Fact]
    public void It_should_add_a_named_instance_from_the_environment_alone()
    {
        var configuration = ConfigComposition.Build(
            PresetDemo.Landscape,
            new Dictionary<string, string?>(StringComparer.Ordinal)
            {
                ["ATOMI_CACHE__SESSIONS__HOST"] = "sessions.internal",
                ["ATOMI_CACHE__SESSIONS__PORT"] = "6379",
                ["ATOMI_CACHE__SESSIONS__DB"] = "2",
            });
        using var provider = ConfigComposition.Provider(configuration);

        var block = Block<CacheBlock>(provider);
        block.Should().HaveCount(2);
        block.Named("SESSIONS").Db.Should().Be(2);
    }

    [Fact]
    public void It_should_compose_every_registered_block_into_the_root_schema()
    {
        var schema = ConfigComposition.Registry().ToJsonSchema();

        schema.Should()
            .Contain("\"App\"")
            .And.Contain("\"Postgres\"")
            .And.Contain("\"Cache\"")
            .And.Contain("\"Kv\"")
            .And.Contain("\"Storage\"");
    }

    [Fact]
    public void It_should_carry_the_service_tree_block()
    {
        var configuration = ConfigComposition.Build(PresetDemo.Landscape, []);
        using var provider = ConfigComposition.Provider(configuration);

        provider.GetRequiredService<IOptions<AppOption>>().Value.Service.Should().Be("standard-config");
    }

    [Fact]
    public void It_should_author_every_connection_name_in_uppercase()
    {
        // The one place the R14 UPPERCASE contract is still observable — the config lib folds
        // the casing away before anything else can check it.
        PresetYamlAudit.ShouldUseUppercaseConnectionNames(
            Path.Combine(AppContext.BaseDirectory, "Config"),
            "settings*.yaml");
    }

    [Fact]
    public void It_should_run_the_whole_network_free_demo()
    {
        var lines = PresetDemo.Run();

        lines.Should().HaveCount(9);
        lines[0].Should().Contain("6379").And.Contain("6381");
        lines[2].Should().Contain("main, replica");
        lines[3].Should().Contain("UPPERCASE");
        lines[4].Should().Contain("4 hand-built blocks valid = True");
        lines[5].Should().Contain("ANALYTICS");
        lines[6].Should().Contain("None registers 0").And.Contain("one-at-a-time registers 4");
        lines[7].Should().Contain("app.fly.storage.tigris.dev");
        lines[8].Should().Contain("5 blocks");
    }

    [Fact]
    public void It_should_refuse_to_reload_on_change()
    {
        var source = ConfigComposition.Source(PresetDemo.Landscape);

        source.ReloadOnChange.Should().BeFalse();
        source.EnvPrefix.Should().Be("ATOMI_");
    }

    [Fact]
    public void It_should_build_from_the_process_environment_too()
    {
        // The overload a real service actually calls.
        var configuration = ConfigComposition.Build(PresetDemo.Landscape);

        configuration["kv:main:port"].Should().Be("6381");
    }

    [Fact]
    public void It_should_reject_a_null_configuration()
    {
        var provider = () => ConfigComposition.Provider(null!);
        provider.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_service_collection()
    {
        var register = () => ConfigComposition.Register(null!);
        register.Should().Throw<ArgumentNullException>();
    }

    private static TBlock Block<TBlock>(IServiceProvider provider)
        where TBlock : class =>
        provider.GetRequiredService<IOptions<TBlock>>().Value;
}
