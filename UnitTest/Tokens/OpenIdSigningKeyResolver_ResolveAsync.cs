using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using FluentAssertions;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace AtomiCloud.DotnetBase.UnitTest.Tokens;

public class OpenIdSigningKeyResolver_ResolveAsync
{
    /// <summary>A configuration manager the test drives, standing in for a discovery endpoint.</summary>
    private sealed class StubConfigurationManager(OpenIdConnectConfiguration? configuration, Exception? failure = null)
        : IConfigurationManager<OpenIdConnectConfiguration>
    {
        public Task<OpenIdConnectConfiguration> GetConfigurationAsync(CancellationToken cancel) =>
            failure is not null
                ? Task.FromException<OpenIdConnectConfiguration>(failure)
                : Task.FromResult(configuration!);

        public void RequestRefresh()
        {
        }
    }

    private static OpenIdConnectConfiguration WithKeys(params SecurityKey[] keys)
    {
        var configuration = new OpenIdConnectConfiguration();
        foreach (var key in keys) configuration.SigningKeys.Add(key);
        return configuration;
    }

    [Fact]
    public async Task Returns_the_discovery_documents_signing_keys()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var resolver = new OpenIdSigningKeyResolver(new StubConfigurationManager(WithKeys(issuer.PublicKey)));

        var outcome = await resolver.ResolveAsync(TestContext.Current.CancellationToken);

        outcome.Get().Should().ContainSingle();
    }

    [Fact]
    public async Task Reports_an_empty_key_set_as_unreachable_rather_than_as_no_keys()
    {
        // Validating against zero keys would fail every token with a signature error and
        // hide the fact that discovery returned nothing usable — a could-not-look
        // reported as a found-nothing.
        var resolver = new OpenIdSigningKeyResolver(new StubConfigurationManager(WithKeys()));

        var outcome = await resolver.ResolveAsync(TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("could not be reached");
    }

    [Theory]
    [MemberData(nameof(TransportFailures))]
    public async Task Converts_a_retrieval_failure_into_a_typed_result(Exception failure)
    {
        var resolver = new OpenIdSigningKeyResolver(new StubConfigurationManager(null, failure));

        var outcome = await resolver.ResolveAsync(TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("could not be reached");
    }

    public static TheoryData<Exception> TransportFailures() =>
    [
        new HttpRequestException("no route"),
        new InvalidOperationException("bad document"),
        new IOException("socket closed"),
        new TaskCanceledException("timed out"),
    ];

    [Fact]
    public async Task Lets_an_unexpected_exception_surface_rather_than_masking_it()
    {
        // Only the enumerated transport shapes become a typed failure. Catching
        // everything would turn a genuine programming error into "the IdP is down".
        var resolver = new OpenIdSigningKeyResolver(
            new StubConfigurationManager(null, new ArgumentException("bug")));

        await FluentActions.Awaiting(() => resolver.ResolveAsync(TestContext.Current.CancellationToken))
            .Should().ThrowAsync<ArgumentException>();
    }

    [Fact]
    public void Builds_a_discovery_url_from_the_configured_origin()
    {
        using var http = new HttpClient(new StubHttpMessageHandler());

        FluentActions.Invoking(() => new OpenIdSigningKeyResolver(AuthEngineFixture.Config(), http))
            .Should().NotThrow();
    }

    [Fact]
    public void Rejects_null_construction_arguments()
    {
        using var http = new HttpClient(new StubHttpMessageHandler());

        FluentActions.Invoking(() => new OpenIdSigningKeyResolver(null!, http))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new OpenIdSigningKeyResolver(AuthEngineFixture.Config(), null!))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() =>
                new OpenIdSigningKeyResolver((IConfigurationManager<OpenIdConnectConfiguration>)null!))
            .Should().Throw<ArgumentNullException>();
    }
}
