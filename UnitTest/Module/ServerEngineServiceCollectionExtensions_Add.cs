using System.Text.Json;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.CoreUtils;
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
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

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
        services.AddAtomiWebhookHandler<StripeHandler>();
        var actual = services.BuildServiceProvider().GetServices<IWebhookHandler>();

        // Assert
        actual.Should().ContainSingle().Which.Should().BeOfType<StripeHandler>();
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
            ServerEngineServiceCollectionExtensions.AddAtomiWebhookHandler<StripeHandler>(null!);
        var secretsWithoutServices = () =>
            ServerEngineServiceCollectionExtensions.AddAtomiWebhookSecrets(null!, "key");

        // Assert
        withoutServices.Should().Throw<ArgumentNullException>();
        withoutConfig.Should().Throw<ArgumentNullException>();
        handlerWithoutServices.Should().Throw<ArgumentNullException>();
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

    [Fact]
    public void It_should_produce_options_that_round_trip_the_contract_forms()
    {
        // Arrange — asserting the settings alone would pass on a converter set that does not
        // actually serialize an instant or an enum the contract's way.
        var options = new JsonSerializerOptions();
        ServerEngineServiceCollectionExtensions.ApplyWireContract(options);
        var instant = new DateTimeOffset(2026, 3, 4, 5, 6, 7, TimeSpan.FromHours(8));

        // Act
        var actual = JsonSerializer.Serialize(new WireProbe(instant, ProbeKind.SecondValue, null), options);

        // Assert
        actual.Should().Be($$"""{"at":"{{Wire.Format(instant)}}","kind":"second_value"}""");
    }

    [Fact]
    public void It_should_refuse_null_serializer_options()
    {
        // Act
        var act = () => ServerEngineServiceCollectionExtensions.ApplyWireContract(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    private enum ProbeKind
    {
        FirstValue = 0,
        SecondValue = 1,
    }

    private sealed record WireProbe(DateTimeOffset At, ProbeKind Kind, string? Absent);

    private sealed class StripeHandler : IWebhookHandler
    {
        public string Provider => "stripe";

        public Task<AtomiCloud.Diene.Results.Result<WebhookOutcome, AtomiCloud.Diene.Problems.IDomainProblem>>
            HandleAsync(WebhookEnvelope envelope, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }
}
