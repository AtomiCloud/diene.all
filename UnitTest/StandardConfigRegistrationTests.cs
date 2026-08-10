using AtomiCloud.Diene.Config;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace AtomiCloud.DotnetBase.UnitTest;

public class StandardConfigRegistrationTests
{
    private static IConfiguration Configuration(params (string Key, string Value)[] values) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(values.Select(pair => new KeyValuePair<string, string?>(pair.Key, pair.Value)))
            .Build();

    private static ServiceProvider Provider(IConfiguration configuration, StandardConfigPreset presets)
    {
        var services = new ServiceCollection();
        services.AddSingleton(configuration);
        services.AddStandardConfigs(presets);
        return services.BuildServiceProvider();
    }

    private static (string Key, string Value)[] PostgresValues(string name = "main") =>
    [
        ($"postgres:{name}:host", "localhost"),
        ($"postgres:{name}:port", "5432"),
        ($"postgres:{name}:database", "app"),
        ($"postgres:{name}:username", "app"),
        ($"postgres:{name}:password", ""),
        ($"postgres:{name}:ssl", "false"),
        ($"postgres:{name}:pool:min", "0"),
        ($"postgres:{name}:pool:max", "10"),
    ];

    [Fact]
    public void It_should_bind_a_keyed_postgres_block()
    {
        using var provider = Provider(Configuration(PostgresValues()), StandardConfigPreset.Postgres);

        var block = provider.GetRequiredService<IOptions<PostgresBlock>>().Value;

        block.Named("MAIN").Database.Should().Be("app");
        block.Named("MAIN").Pool.Max.Should().Be(10);
    }

    [Fact]
    public void It_should_bind_a_second_named_instance_without_a_schema_change()
    {
        using var provider = Provider(
            Configuration([.. PostgresValues(), .. PostgresValues("replica")]),
            StandardConfigPreset.Postgres);

        var block = provider.GetRequiredService<IOptions<PostgresBlock>>().Value;

        block.Should().HaveCount(2);
        block.Named("REPLICA").Username.Should().Be("app");
    }

    [Fact]
    public void It_should_fail_at_resolution_when_a_pool_name_is_malformed()
    {
        using var provider = Provider(Configuration(PostgresValues("my@pool")), StandardConfigPreset.Postgres);

        var resolve = () => provider.GetRequiredService<IOptions<PostgresBlock>>().Value;

        resolve.Should().Throw<OptionsValidationException>().WithMessage("*UPPERCASE*");
    }

    [Fact]
    public void It_should_fail_at_resolution_when_an_entry_is_invalid()
    {
        using var provider = Provider(
            Configuration([("postgres:main:host", ""), ("postgres:main:port", "5432")]),
            StandardConfigPreset.Postgres);

        var resolve = () => provider.GetRequiredService<IOptions<PostgresBlock>>().Value;

        resolve.Should().Throw<OptionsValidationException>();
    }

    [Theory]
    [InlineData(StandardConfigPreset.Postgres, typeof(PostgresBlock))]
    [InlineData(StandardConfigPreset.Cache, typeof(CacheBlock))]
    [InlineData(StandardConfigPreset.Kv, typeof(KvBlock))]
    [InlineData(StandardConfigPreset.Storage, typeof(StorageBlock))]
    public void It_should_register_only_the_presets_it_was_asked_for(StandardConfigPreset preset, Type block)
    {
        var services = new ServiceCollection();
        services.AddSingleton(Configuration());
        services.AddStandardConfigs(preset);

        var registry = Registry(services);

        registry.Blocks.Values.Should().ContainSingle()
            .Which.Should().Be(block);
    }

    [Fact]
    public void It_should_register_every_preset_under_its_frozen_key()
    {
        var services = new ServiceCollection();
        services.AddSingleton(Configuration());
        services.AddStandardConfigs(StandardConfigPreset.All);

        Registry(services).Blocks.Keys.Should().BeEquivalentTo(["Postgres", "Cache", "Kv", "Storage"]);
    }

    [Fact]
    public void It_should_register_nothing_for_the_empty_preset_set()
    {
        var services = new ServiceCollection();
        services.AddSingleton(Configuration());
        services.AddStandardConfigs(StandardConfigPreset.None);

        services.Should().NotContain(descriptor => descriptor.ServiceType == typeof(IConfigSchemaRegistry));
    }

    [Fact]
    public void It_should_expose_each_preset_as_its_own_entry_point()
    {
        var services = new ServiceCollection();
        services.AddSingleton(Configuration());

        services.AddPostgresPreset().AddCachePreset().AddKvPreset().AddStoragePreset();

        Registry(services).Blocks.Should().HaveCount(4);
    }

    [Fact]
    public void It_should_reject_a_null_service_collection()
    {
        var add = () => StandardConfigRegistration.AddStandardConfigs(null!, StandardConfigPreset.All);
        add.Should().Throw<ArgumentNullException>();
    }

    private static ConfigSchemaRegistry Registry(IServiceCollection services) =>
        (ConfigSchemaRegistry)services
            .First(descriptor => descriptor.ServiceType == typeof(IConfigSchemaRegistry))
            .ImplementationInstance!;
}
