using AtomiCloud.Diene.Config.TestHelper;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace AtomiCloud.DotnetBase.UnitTest;

/// <summary>
/// Meta tier — fixture invariants. The fixture's whole claim is that its three fake layers
/// have the same precedence as the real ones, so that is what these prove.
/// </summary>
public class MetaConfigFixtureTests
{
    [Fact]
    public void The_landscape_layer_beats_the_base_layer()
    {
        var config = new AtomiConfigFixture()
            .WithBase("error_portal:host", "base")
            .WithLandscape("error_portal:host", "landscape")
            .Build();

        config["errorportal:host"].Should().Be("landscape");
    }

    [Fact]
    public void The_environment_layer_beats_both()
    {
        var config = new AtomiConfigFixture()
            .WithBase("error_portal:host", "base")
            .WithLandscape("error_portal:host", "landscape")
            .WithEnvironment("ERROR_PORTAL__HOST", "environment")
            .Build();

        config["errorportal:host"].Should().Be("environment");
    }

    [Fact]
    public void A_sparse_landscape_layer_leaves_untouched_base_keys_alone()
    {
        var config = new AtomiConfigFixture()
            .WithBase("error_portal:host", "base")
            .WithBase("error_portal:scheme", "https")
            .WithLandscape("error_portal:host", "landscape")
            .Build();

        config["errorportal:scheme"].Should().Be("https");
    }

    [Fact]
    public void WithSecret_declares_the_key_blank_and_injects_it_from_the_environment()
    {
        var config = new AtomiConfigFixture()
            .WithSecret("error_portal:signing_key", "ERROR_PORTAL__SIGNING_KEY", "injected")
            .Build();

        config["errorportal:signingkey"].Should().Be("injected");
    }

    [Fact]
    public void The_environment_prefix_is_configurable_because_the_library_bakes_none()
    {
        var config = new AtomiConfigFixture { EnvPrefix = "OTHER_" }
            .WithEnvironment("HOST", "alpha")
            .Build();

        config["host"].Should().Be("alpha");
    }

    [Fact]
    public void A_variable_carrying_the_wrong_prefix_reaches_nothing()
    {
        var config = new AtomiConfigFixture { EnvPrefix = "OTHER_" }.Build();

        config["host"].Should().BeNull();
    }

    [Fact]
    public void Indexed_environment_keys_build_a_list()
    {
        var config = new AtomiConfigFixture()
            .WithEnvironment("HOSTS__0", "alpha")
            .WithEnvironment("HOSTS__1", "beta")
            .Build();

        config.GetSection("hosts").GetChildren().Select(child => child.Value)
            .Should().Equal("alpha", "beta");
    }

    [Fact]
    public void BuildProvider_hands_back_a_provider_over_the_merged_configuration()
    {
        using var provider = new AtomiConfigFixture()
            .WithBase("error_portal:host", "alpha")
            .BuildProvider(services => services.RegisterOption<PortalOption>(PortalOption.Key));

        provider.GetRequiredService<IOptions<PortalOption>>().Value.Host.Should().Be("alpha");
    }

    [Fact]
    public void Resolve_returns_the_bound_block_when_it_validates()
    {
        var result = new AtomiConfigFixture()
            .WithBase("error_portal:host", "alpha")
            .Resolve<PortalOption>(services => services.RegisterOption<PortalOption>(PortalOption.Key));

        result.IsSuccess(out var option).Should().BeTrue();
        option!.Host.Should().Be("alpha");
    }

    [Fact]
    public void Resolve_returns_the_failure_instead_of_throwing_so_fail_fast_reads_as_a_value()
    {
        var result = new AtomiConfigFixture()
            .WithBase("error_portal:host", "no")
            .Resolve<PortalOption>(services => services.RegisterOption<PortalOption>(PortalOption.Key));

        result.IsFailure(out var message).Should().BeTrue();
        message.Should().Contain("Host");
    }

    [Fact]
    public void Every_builder_call_returns_the_fixture_so_calls_chain()
    {
        var fixture = new AtomiConfigFixture();

        fixture.WithBase("a", "1").Should().BeSameAs(fixture);
        fixture.WithLandscape("a", "1").Should().BeSameAs(fixture);
        fixture.WithEnvironment("A", "1").Should().BeSameAs(fixture);
        fixture.WithSecret("b", "B", "1").Should().BeSameAs(fixture);
    }

    [Fact]
    public void WithEnvironment_rejects_a_blank_name() =>
        FluentActions.Invoking(() => new AtomiConfigFixture().WithEnvironment("  ", "v"))
            .Should().Throw<ArgumentException>();

    [Fact]
    public void BuildProvider_rejects_a_null_registration() =>
        FluentActions.Invoking(() => new AtomiConfigFixture().BuildProvider(null!))
            .Should().Throw<ArgumentNullException>();
}
