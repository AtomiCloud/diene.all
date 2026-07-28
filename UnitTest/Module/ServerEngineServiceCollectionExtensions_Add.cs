using System.Text.Json;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.CoreUtils;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.ServerEngine.Config;
using AtomiCloud.Diene.ServerEngine.Module;
using AtomiCloud.Diene.ServerEngine.Mvc;
using AtomiCloud.Diene.ServerEngine.Onboarding;
using AtomiCloud.Diene.ServerEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Infrastructure;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.UnitTest.Module;

public class ServerEngineServiceCollectionExtensions_Add
{
    [Fact]
    public void It_should_name_every_controller_it_mounts()
    {
        // Act
        var actual = ServerEngineServiceCollectionExtensions.ShippedControllers;

        // Assert
        actual.Should().Equal([
            typeof(SystemController),
            typeof(WebhookController),
            typeof(OnboardSyncController),
        ]);
    }

    [Fact]
    public async Task It_should_actually_discover_every_controller_it_claims_to_mount()
    {
        // Arrange — application-part registration fails SILENTLY: a service would simply 404
        // routes it believes it exposes. Comparing the claim against the real route table is the
        // only thing that makes the failure visible.
        await using var host = await ServerEngineTestHost.StartAsync();
        var routes = host.Services.GetRequiredService<IActionDescriptorCollectionProvider>();

        // Act
        var actual = routes.ActionDescriptors.Items
            .Select(descriptor => descriptor.DisplayName ?? string.Empty)
            .ToArray();

        // Assert
        foreach (var controller in ServerEngineServiceCollectionExtensions.ShippedControllers)
        {
            actual.Should().Contain(name => name.Contains(controller.FullName!, StringComparison.Ordinal));
        }
    }

    [Fact]
    public void It_should_register_a_webhook_handler_under_the_handler_seam()
    {
        // Arrange
        var services = new ServiceCollection();

        // Act
        services.AddAtomiWebhookHandler(_ => new StripeHandler());
        var actual = services.BuildServiceProvider().GetServices<IWebhookHandler>();

        // Assert
        actual.Should().ContainSingle().Which.Should().BeOfType<StripeHandler>();
    }

    [Fact]
    public void It_should_let_a_handler_factory_resolve_its_own_dependencies()
    {
        // Arrange — a real handler needs a repository or a client, which is why the seam takes a
        // factory rather than a bare type argument.
        var services = new ServiceCollection();
        services.AddSingleton("dependency");

        // Act
        services.AddAtomiWebhookHandler(provider => new DependentHandler(provider.GetRequiredService<string>()));
        var actual = services.BuildServiceProvider().GetRequiredService<IWebhookHandler>();

        // Assert
        actual.Should().BeOfType<DependentHandler>().Which.Dependency.Should().Be("dependency");
    }

    [Fact]
    public void It_should_register_every_supplied_signing_key()
    {
        // Arrange
        var services = new ServiceCollection();

        // Act
        services.AddAtomiWebhookSecrets("one", "two");
        var actual = services.BuildServiceProvider().GetRequiredService<IWebhookSecretProvider>();

        // Assert
        actual.SigningKeys.Should().Equal(["one", "two"]);
    }

    [Fact]
    public void It_should_leave_a_secret_provider_a_host_already_registered_alone()
    {
        // Arrange — a test host that substituted its own provider must keep it, or the
        // substitution would be silently overridden far from where it was made.
        var services = new ServiceCollection();
        var fake = new FakeWebhookSecretProvider("host-key");
        services.AddSingleton<IWebhookSecretProvider>(fake);

        // Act
        services.AddAtomiWebhookSecrets("engine-key");
        var actual = services.BuildServiceProvider().GetRequiredService<IWebhookSecretProvider>();

        // Assert
        actual.Should().BeSameAs(fake);
    }

    [Fact]
    public void It_should_refuse_a_null_service_collection_or_config()
    {
        // Arrange
        var config = ServerEngineConfig
            .Create(ServiceIdentityConfig.Create("lapras", "sulfoxide", "probe", "api", "1.0.0").Get(), WebhookConfig.Default)
            .Get();

        // Act
        var withoutServices = () => ServerEngineServiceCollectionExtensions.AddAtomiServerEngine(null!, config);
        var withoutConfig = () => new ServiceCollection().AddAtomiServerEngine(null!);
        var handlerWithoutServices = () =>
            ServerEngineServiceCollectionExtensions.AddAtomiWebhookHandler(null!, _ => new StripeHandler());
        var handlerWithoutFactory = () =>
            new ServiceCollection().AddAtomiWebhookHandler<StripeHandler>(null!);
        var secretsWithoutServices = () =>
            ServerEngineServiceCollectionExtensions.AddAtomiWebhookSecrets(null!, "key");

        // Assert
        withoutServices.Should().Throw<ArgumentNullException>();
        withoutConfig.Should().Throw<ArgumentNullException>();
        handlerWithoutServices.Should().Throw<ArgumentNullException>();
        handlerWithoutFactory.Should().Throw<ArgumentNullException>();
        secretsWithoutServices.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_apply_the_whole_wire_contract_to_options_a_host_owns()
    {
        // Arrange
        var options = new JsonSerializerOptions();

        // Act
        ServerEngineServiceCollectionExtensions.ApplyWireContract(options);

        // Assert
        options.PropertyNamingPolicy.Should().Be(JsonNamingPolicy.CamelCase);
        options.DictionaryKeyPolicy.Should().Be(JsonNamingPolicy.CamelCase);
        options.NumberHandling.Should().Be(JsonNumberHandling.Strict);
        options.DefaultIgnoreCondition.Should().Be(JsonIgnoreCondition.WhenWritingNull);
        options.Converters.Should().ContainItemsAssignableTo<JsonStringEnumConverter>();
    }

    [Theory]
    [ClassData(typeof(EnumNameCases))]
    public void It_should_produce_options_that_round_trip_the_contract_forms(ProbeKind kind, string wireName)
    {
        // Arrange — asserting the settings alone would pass on a converter set that does not
        // actually serialize an instant or an enum the contract's way.
        var options = new JsonSerializerOptions();
        ServerEngineServiceCollectionExtensions.ApplyWireContract(options);
        var instant = new DateTimeOffset(2026, 3, 4, 5, 6, 7, TimeSpan.FromHours(8));

        // Act
        var json = JsonSerializer.Serialize(new WireProbe(instant, kind, null), options);
        var actual = JsonSerializer.Deserialize<WireProbe>(json, options);

        // Assert
        json.Should().Be($$"""{"at":"{{Wire.Format(instant)}}","kind":"{{wireName}}"}""");
        actual!.At.Should().Be(instant.ToUniversalTime());
        actual.Kind.Should().Be(kind);
        actual.Absent.Should().BeNull();
    }

    [Fact]
    public void It_should_refuse_null_serializer_options()
    {
        // Act
        var act = () => ServerEngineServiceCollectionExtensions.ApplyWireContract(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    /// <summary>A two-member enum, so a snake_case name is distinguishable from an ordinal.</summary>
    public enum ProbeKind
    {
        /// <summary>The first member, whose ordinal is zero.</summary>
        FirstValue = 0,

        /// <summary>The second member, whose ordinal is one.</summary>
        SecondValue = 1,
    }

    private sealed record WireProbe(DateTimeOffset At, ProbeKind Kind, string? Absent);

    private sealed class EnumNameCases : TheoryData<ProbeKind, string>
    {
        public EnumNameCases()
        {
            this.Add(ProbeKind.FirstValue, "first_value");
            this.Add(ProbeKind.SecondValue, "second_value");
        }
    }

    private sealed class StripeHandler : IWebhookHandler
    {
        public string Provider => "stripe";

        public Task<Result<WebhookOutcome, IDomainProblem>> HandleAsync(
            WebhookEnvelope envelope,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }

    private sealed class DependentHandler(string dependency) : IWebhookHandler
    {
        public string Provider => "paypal";

        public string Dependency { get; } = dependency;

        public Task<Result<WebhookOutcome, IDomainProblem>> HandleAsync(
            WebhookEnvelope envelope,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }
}
