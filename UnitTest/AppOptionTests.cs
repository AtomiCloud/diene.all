using AtomiCloud.Diene.Config.TestHelper;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.UnitTest;

public class AppOptionTests
{
    private static AtomiConfigFixture Complete() => new AtomiConfigFixture()
        .WithBase("app:landscape", "lapras")
        .WithBase("app:platform", "diene")
        .WithBase("app:service", "config")
        .WithBase("app:module", "demo")
        .WithBase("app:version", "1.0.0");

    private static Result<AppOption, string> Resolve(AtomiConfigFixture fixture) =>
        fixture.Resolve<AppOption>(services => services.AddAtomiServiceTree());

    [Fact]
    public void The_service_tree_block_binds_from_a_snake_cased_layer()
    {
        var app = Resolve(Complete()).Get();

        app.Landscape.Should().Be("lapras");
        app.Platform.Should().Be("diene");
        app.Service.Should().Be("config");
        app.Module.Should().Be("demo");
        app.Version.Should().Be("1.0.0");
    }

    [Fact]
    public void The_block_key_is_App() => AppOption.Key.Should().Be("App");

    [Theory]
    [InlineData("app:landscape")]
    [InlineData("app:platform")]
    [InlineData("app:service")]
    [InlineData("app:module")]
    public void A_missing_service_tree_field_stops_the_service_at_startup(string key)
    {
        var failure = Resolve(Complete().WithBase(key, ""));

        failure.IsFailure().Should().BeTrue();
    }

    [Theory]
    [InlineData("1.0")]
    [InlineData("v1.0.0")]
    [InlineData("")]
    public void A_version_that_is_not_three_numbers_is_rejected(string version) =>
        Resolve(Complete().WithBase("app:version", version)).IsFailure().Should().BeTrue();

    [Fact]
    public void A_one_character_field_is_too_short_to_be_a_service_tree_name() =>
        Resolve(Complete().WithBase("app:service", "x")).IsFailure().Should().BeTrue();

    [Fact]
    public void An_environment_override_supplies_the_landscape_like_a_real_deployment()
    {
        var app = Resolve(Complete().WithEnvironment("APP__LANDSCAPE", "mareep")).Get();

        app.Landscape.Should().Be("mareep");
    }

    [Fact]
    public void AddAtomiServiceTree_registers_the_block_in_the_schema_registry()
    {
        var services = new ServiceCollection();
        services.AddAtomiServiceTree();

        var registry = (ConfigSchemaRegistry)services.BuildServiceProvider()
            .GetRequiredService<IConfigSchemaRegistry>();

        registry.Blocks.Should().ContainKey(AppOption.Key);
    }

    [Fact]
    public void AddAtomiServiceTree_rejects_a_null_service_collection() =>
        FluentActions.Invoking(() => ((IServiceCollection)null!).AddAtomiServiceTree())
            .Should().Throw<ArgumentNullException>();
}
