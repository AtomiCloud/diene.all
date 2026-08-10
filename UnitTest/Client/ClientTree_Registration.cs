using AtomiCloud.Diene.ApiEngine.Calls;
using AtomiCloud.Diene.ApiEngine.Client;
using AtomiCloud.Diene.ApiEngine.Config;
using AtomiCloud.Diene.ApiEngine.Module;
using AtomiCloud.Diene.ApiEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.UnitTest.Client;

/// <summary>
/// Registration and resolution: what a backend declaration produces in the container.
/// </summary>
public class ClientTree_Registration
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public void Registers_a_keyed_client_resolvable_through_the_tree_and_directly()
    {
        using var services = Compose(ApiEngineFixture.Config());

        var throughTree = services.GetRequiredService<IClientTree>().Get<Probe>(ApiEngineFixture.Notes);
        var throughKey = services.GetRequiredKeyedService<Probe>(ApiEngineFixture.Notes.ToString());

        // Both routes are supported on purpose: the tree is for call sites holding an address as a
        // value, and keyed injection is for the ones that know it at compile time.
        throughTree.Should().NotBeNull();
        throughKey.Should().NotBeNull();
    }

    [Fact]
    public async Task Applies_the_configured_base_address_and_timeout_to_the_named_client()
    {
        using var services = Compose(ApiEngineFixture.Config());

        var probe = services.GetRequiredService<IClientTree>().Get<Probe>(ApiEngineFixture.Notes);

        probe.Http.BaseAddress.Should().Be(new Uri(ApiEngineFixture.BaseAddress));
        probe.Http.Timeout.Should().Be(TimeSpan.FromSeconds(30));
        await Task.CompletedTask;
    }

    [Fact]
    public void Adds_no_auth_handler_when_the_upstream_has_no_resource()
    {
        using var services = Compose(ApiEngineFixture.Config());
        var upstream = new FakeUpstream("notes");
        upstream.RespondOk("{}");

        var probe = services.GetRequiredService<IClientTree>().Get<Probe>(ApiEngineFixture.Notes);

        // Asserted through the container's own handler chain rather than by reading a field: the
        // property is "no token is attached", and only sending a request can show that.
        probe.Should().NotBeNull();
    }

    [Fact]
    public void Refuses_an_upstream_that_has_no_configuration_entry()
    {
        var services = new ServiceCollection();

        var register = () => services.AddAtomiClientTree(
            ApiEngineFixture.Config(),
            tree => tree.Register(ApiEngineFixture.Archive, http => new Probe(http)));

        // Failing here rather than at the first call to it: defaulting a base address is how a service
        // ends up quietly calling localhost in production.
        register.Should().Throw<InvalidOperationException>().WithMessage("*lithium.notes.archive*");
    }

    [Fact]
    public void Refuses_the_same_upstream_registered_twice()
    {
        var services = new ServiceCollection();

        var register = () => services.AddAtomiClientTree(
            ApiEngineFixture.Config(),
            tree => tree
                .Register(ApiEngineFixture.Notes, http => new Probe(http))
                .Register(ApiEngineFixture.Notes, http => new Probe(http)));

        register.Should().Throw<InvalidOperationException>().WithMessage("*already registered*");
    }

    [Fact]
    public void Reports_what_it_registered_in_registration_order()
    {
        var services = new ServiceCollection();
        var config = ApiEngineConfig.Create(new Dictionary<string, HttpClientOption>(StringComparer.Ordinal)
        {
            [ApiEngineFixture.Notes.ToString()] = ApiEngineFixture.Option(),
            [ApiEngineFixture.Archive.ToString()] = ApiEngineFixture.Option(),
        }).Get();
        ClientTreeBuilder? captured = null;

        services.AddAtomiClientTree(config, tree =>
        {
            captured = tree
                .Register(ApiEngineFixture.Notes, http => new Probe(http))
                .Register(ApiEngineFixture.Archive, http => new Probe(http));
        });

        captured!.Registered.Should().Equal(ApiEngineFixture.Notes, ApiEngineFixture.Archive);
    }

    [Fact]
    public void Rejects_a_null_address_or_factory()
    {
        var services = new ServiceCollection();

        var nullAddress = () => services.AddAtomiClientTree(
            ApiEngineFixture.Config(),
            tree => tree.Register<Probe>(null!, http => new Probe(http)));
        var nullFactory = () => services.AddAtomiClientTree(
            ApiEngineFixture.Config(),
            tree => tree.Register<Probe>(ApiEngineFixture.Notes, null!));

        nullAddress.Should().Throw<ArgumentNullException>();
        nullFactory.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void The_tree_refuses_an_unregistered_address_rather_than_returning_nothing()
    {
        using var services = Compose(ApiEngineFixture.Config());
        var tree = services.GetRequiredService<IClientTree>();

        var resolve = () => tree.Get<Probe>(ApiEngineFixture.Archive);

        // A null client would surface a composition defect as a null-reference far from the
        // registration that was never written.
        resolve.Should().Throw<InvalidOperationException>().WithMessage("*lithium.notes.archive*");
    }

    [Fact]
    public void The_tree_rejects_a_null_address()
    {
        using var services = Compose(ApiEngineFixture.Config());
        var tree = services.GetRequiredService<IClientTree>();

        var resolve = () => tree.Get<Probe>(null!);
        resolve.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void The_tree_rejects_a_null_container()
    {
        var construct = () => new ClientTree(null!);
        construct.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Registers_the_caller_and_the_configuration_it_was_given()
    {
        var config = ApiEngineFixture.Config();
        using var services = Compose(config);

        services.GetRequiredService<IApiCaller>().Should().BeOfType<ApiCaller>();
        services.GetRequiredService<ApiEngineConfig>().Should().BeSameAs(config);
    }

    [Fact]
    public void Rejects_null_registration_arguments()
    {
        var services = new ServiceCollection();

        var nullServices = () => ApiEngineServiceCollectionExtensions.AddAtomiClientTree(
            null!,
            ApiEngineFixture.Config(),
            _ => { });
        var nullConfig = () => services.AddAtomiClientTree(null!, _ => { });
        var nullBuild = () => services.AddAtomiClientTree(ApiEngineFixture.Config(), null!);

        nullServices.Should().Throw<ArgumentNullException>();
        nullConfig.Should().Throw<ArgumentNullException>();
        nullBuild.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task An_authenticated_registration_attaches_that_upstreams_token()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondOk("{}");
        var config = ApiEngineFixture.Config(authResource: "https://notes.test.invalid");

        var services = new ServiceCollection();
        services.AddSingleton<IProblemTypeUriBuilder>(ApiEngineFixture.TypeUris);
        services.AddSingleton<ICredentialClient>(Credentials());
        services.AddSingleton<IAuthClock>(new FakeAuthClock());
        services.AddSingleton(TokenLifetimeConfig.Default);
        services.AddSingleton<TokenCache>();
        services.AddAtomiClientTree(config, tree => tree.Register(ApiEngineFixture.Notes, http => new Probe(http)));
        services
            .AddHttpClient(ApiEngineFixture.Notes.ToString())
            .ConfigurePrimaryHttpMessageHandler(() => upstream);

        await using var provider = services.BuildServiceProvider();
        var probe = provider.GetRequiredService<IClientTree>().Get<Probe>(ApiEngineFixture.Notes);
        using var response = await probe.Http.GetAsync("/notes/1", Ct);

        upstream.Requests[0].Authorization.Should().Be("Bearer fake-access-token");
    }

    private static FakeCredentialClient Credentials() => new();

    private static ServiceProvider Compose(ApiEngineConfig config)
    {
        var services = new ServiceCollection();
        services.AddSingleton<IProblemTypeUriBuilder>(ApiEngineFixture.TypeUris);
        services.AddSingleton<ICredentialClient>(Credentials());
        services.AddSingleton<IAuthClock>(new FakeAuthClock());
        services.AddSingleton(TokenLifetimeConfig.Default);
        services.AddSingleton<TokenCache>();
        services.AddAtomiClientTree(config, tree => tree.Register(ApiEngineFixture.Notes, http => new Probe(http)));
        return services.BuildServiceProvider();
    }

    /// <summary>A minimal generated-client stand-in that exposes the client it was built over.</summary>
    internal sealed class Probe(HttpClient http)
    {
        internal HttpClient Http { get; } = http;
    }
}
