using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace AtomiCloud.DotnetBase.IntTest;

/// <summary>
/// Exercises the demo consumer against its REAL YAML files on disk — the layering contract
/// end to end, rather than through in-memory fakes.
/// </summary>
public class ConfigCompositionTests
{
    private static readonly KeyValuePair<string, string?>[] Complete =
    [
        new("ATOMI_ERROR_PORTAL__SIGNING_KEY", "injected"),
    ];

    [Fact]
    public void The_base_file_supplies_defaults_the_overlay_does_not_mention() =>
        ConfigComposition.Build("lapras", Complete)["errorportal:scheme"].Should().Be("https");

    [Fact]
    public void The_landscape_file_overrides_the_base_file() =>
        ConfigComposition.Build("lapras", Complete)["errorportal:host"]
            .Should().Be("docs.lapras.atomi.cloud");

    [Fact]
    public void An_absent_landscape_file_leaves_the_base_value_standing() =>
        ConfigComposition.Build("no-such-landscape", Complete)["errorportal:host"]
            .Should().Be("docs.atomi.cloud");

    [Fact]
    public void An_environment_variable_overrides_both_files() =>
        ConfigComposition.Build("lapras", [.. Complete, new("ATOMI_ERROR_PORTAL__HOST", "from-env")])
            ["errorportal:host"].Should().Be("from-env");

    [Fact]
    public void A_yaml_list_binds_as_a_collection()
    {
        var configuration = ConfigComposition.Build("lapras", Complete);
        using var provider = ConfigComposition.Provider(configuration);

        provider.GetRequiredService<IOptions<ErrorPortalOption>>().Value.RetryHosts
            .Should().Equal("docs-1.atomi.cloud", "docs-2.atomi.cloud");
    }

    [Fact]
    public void An_indexed_environment_key_replaces_one_list_element()
    {
        var configuration = ConfigComposition.Build(
            "lapras",
            [.. Complete, new("ATOMI_ERROR_PORTAL__RETRY_HOSTS__0", "replaced")]);
        using var provider = ConfigComposition.Provider(configuration);

        provider.GetRequiredService<IOptions<ErrorPortalOption>>().Value.RetryHosts
            .Should().Equal("replaced", "docs-2.atomi.cloud");
    }

    [Fact]
    public void The_service_tree_block_binds_from_the_real_file()
    {
        var configuration = ConfigComposition.Build("lapras", Complete);
        using var provider = ConfigComposition.Provider(configuration);

        var app = provider.GetRequiredService<IOptions<AppOption>>().Value;

        app.Service.Should().Be("config");
        app.Version.Should().Be("1.0.0");
    }

    [Fact]
    public void A_secret_that_is_never_injected_stops_the_service_at_startup()
    {
        var configuration = ConfigComposition.Build("lapras", []);
        using var provider = ConfigComposition.Provider(configuration);

        FluentActions.Invoking(() => provider.GetRequiredService<IOptions<ErrorPortalOption>>().Value)
            .Should().Throw<OptionsValidationException>()
            .WithMessage("*SigningKey*must be injected from the environment*");
    }

    [Fact]
    public void The_generated_schema_pointer_on_the_first_line_is_not_a_config_key() =>
        ConfigComposition.Build("lapras", Complete).AsEnumerable().Select(pair => pair.Key)
            .Should().NotContain("$schema");

    [Fact]
    public void The_configured_env_prefix_is_the_apps_choice_not_the_librarys() =>
        ConfigComposition.Source("lapras").EnvPrefix.Should().Be(ConfigComposition.EnvPrefix);

    [Fact]
    public void The_composed_root_schema_holds_every_registered_block()
    {
        var registry = ConfigComposition.Registry();

        ((ConfigSchemaRegistry)registry).Blocks.Keys
            .Should().BeEquivalentTo([AppOption.Key, ErrorPortalOption.Key]);
    }
}
