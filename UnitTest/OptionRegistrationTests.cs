using System.ComponentModel.DataAnnotations;
using AtomiCloud.Diene.Config.TestHelper;
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.UnitTest;

public sealed class PortalOption
{
    public const string Key = "ErrorPortal";

    [Required]
    [MinLength(3)]
    public string Host { get; set; } = "";

    public int Retries { get; set; }
}

public sealed class PortalOptionValidator : AbstractValidator<PortalOption>
{
    public PortalOptionValidator()
    {
        RuleFor(option => option.Host).NotEmpty().WithMessage("must not be blank");
        RuleFor(option => option.Retries).InclusiveBetween(0, 5);
    }
}

public class OptionRegistrationTests
{
    private static AtomiConfigFixture Fixture() => new AtomiConfigFixture()
        .WithBase("error_portal:host", "base-host")
        .WithBase("error_portal:retries", "1");

    [Fact]
    public void DataAnnotations_registration_binds_a_snake_cased_layer_to_pascal_properties()
    {
        var option = Fixture()
            .Resolve<PortalOption>(services => services.RegisterOption<PortalOption>(PortalOption.Key))
            .Get();

        option.Host.Should().Be("base-host");
        option.Retries.Should().Be(1);
    }

    [Fact]
    public void DataAnnotations_registration_fails_fast_on_the_final_merged_layer()
    {
        var failure = new AtomiConfigFixture()
            .WithBase("error_portal:host", "ok")
            .WithEnvironment("ERROR_PORTAL__HOST", "no")
            .Resolve<PortalOption>(services => services.RegisterOption<PortalOption>(PortalOption.Key));

        failure.IsFailure(out var message).Should().BeTrue();
        message.Should().Contain("Host");
    }

    [Fact]
    public void FluentValidation_registration_is_the_standard_path()
    {
        var option = Fixture()
            .Resolve<PortalOption>(services =>
                services.RegisterOption<PortalOption, PortalOptionValidator>(PortalOption.Key))
            .Get();

        option.Host.Should().Be("base-host");
    }

    [Fact]
    public void A_FluentValidation_failure_names_the_config_key_that_is_wrong()
    {
        var failure = new AtomiConfigFixture()
            .WithBase("error_portal:host", "ok")
            .WithBase("error_portal:retries", "99")
            .Resolve<PortalOption>(services =>
                services.RegisterOption<PortalOption, PortalOptionValidator>(PortalOption.Key));

        failure.IsFailure(out var message).Should().BeTrue();
        message.Should().Contain("Config 'ErrorPortal:Retries' is invalid");
    }

    [Fact]
    public void An_environment_override_can_repair_an_invalid_base_layer()
    {
        var option = new AtomiConfigFixture()
            .WithBase("error_portal:host", "")
            .WithEnvironment("ERROR_PORTAL__HOST", "repaired")
            .Resolve<PortalOption>(services =>
                services.RegisterOption<PortalOption, PortalOptionValidator>(PortalOption.Key))
            .Get();

        option.Host.Should().Be("repaired");
    }

    [Fact]
    public void Registering_a_block_records_it_in_the_schema_registry()
    {
        var services = new ServiceCollection();
        services.RegisterOption<PortalOption>(PortalOption.Key);

        var registry = services.BuildServiceProvider().GetRequiredService<IConfigSchemaRegistry>();

        registry.Should().BeOfType<ConfigSchemaRegistry>()
            .Which.Blocks.Should().ContainKey(PortalOption.Key);
    }

    [Fact]
    public void Every_block_in_one_service_collection_lands_in_the_same_registry()
    {
        var services = new ServiceCollection();
        services.RegisterOption<PortalOption>(PortalOption.Key);
        services.RegisterOption<AppOption, AppOptionValidator>(AppOption.Key);

        var registry = (ConfigSchemaRegistry)services.BuildServiceProvider()
            .GetRequiredService<IConfigSchemaRegistry>();

        registry.Blocks.Keys.Should().BeEquivalentTo([PortalOption.Key, AppOption.Key]);
    }

    [Fact]
    public void A_validator_is_an_ordinary_object_that_runs_without_a_host()
    {
        var result = new PortalOptionValidator().Validate(new PortalOption { Host = "", Retries = 9 });

        result.Errors.Select(failure => failure.PropertyName).Should().BeEquivalentTo(["Host", "Retries"]);
    }

    [Fact]
    public void A_valid_block_satisfies_its_validator_directly() =>
        new PortalOptionValidator().Validate(new PortalOption { Host = "alpha", Retries = 3 })
            .IsValid.Should().BeTrue();

    [Fact]
    public void The_service_tree_validator_also_runs_standalone() =>
        new AppOptionValidator().Validate(new AppOption()).IsValid.Should().BeFalse();

    [Fact]
    public void RegisterOption_rejects_a_null_service_collection() =>
        FluentActions.Invoking(() => ((IServiceCollection)null!).RegisterOption<PortalOption>("k"))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void RegisterOption_rejects_a_blank_key() =>
        FluentActions.Invoking(() => new ServiceCollection().RegisterOption<PortalOption>("  "))
            .Should().Throw<ArgumentException>();

    [Fact]
    public void The_validated_overload_rejects_a_null_service_collection() =>
        FluentActions.Invoking(() =>
                ((IServiceCollection)null!).RegisterOption<PortalOption, PortalOptionValidator>("k"))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void The_validated_overload_rejects_a_blank_key() =>
        FluentActions.Invoking(() =>
                new ServiceCollection().RegisterOption<PortalOption, PortalOptionValidator>("  "))
            .Should().Throw<ArgumentException>();
}

public sealed class AppOptionValidator : AbstractValidator<AppOption>
{
    public AppOptionValidator() => RuleFor(option => option.Service).NotEmpty();
}
