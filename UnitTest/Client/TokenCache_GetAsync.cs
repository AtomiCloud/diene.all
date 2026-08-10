using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Client;

public class TokenCache_GetAsync
{
    private const string Resource = "https://api.test.invalid";

    [Fact]
    public async Task Acquires_a_token_on_the_first_call()
    {
        var clock = AuthEngineFixture.Clock();
        var client = new FakeCredentialClient();
        client.ScriptToken(Resource, "token-1", AuthEngineFixture.Now.AddMinutes(10));

        var cache = new TokenCache(client, clock, TokenLifetimeConfig.Default);

        var outcome = await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);

        outcome.Get().Token.Should().Be("token-1");
        client.AcquireCount.Should().Be(1);
    }

    [Fact]
    public async Task Serves_a_second_read_from_cache_without_calling_the_idp()
    {
        var clock = AuthEngineFixture.Clock();
        var client = new FakeCredentialClient();
        client.ScriptToken(Resource, "token-1", AuthEngineFixture.Now.AddMinutes(10));

        var cache = new TokenCache(client, clock, TokenLifetimeConfig.Default);

        await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);
        var second = await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);

        second.Get().Token.Should().Be("token-1");
        client.AcquireCount.Should().Be(1);
    }

    [Fact]
    public async Task Renews_before_expiry_rather_than_after()
    {
        // The renewal must happen while the cached token is still valid, otherwise a
        // request goes out carrying a token that expires in flight.
        var clock = AuthEngineFixture.Clock();
        var client = new FakeCredentialClient();
        client.ScriptToken(Resource, "token-1", AuthEngineFixture.Now.AddMinutes(10));
        client.ScriptToken(Resource, "token-2", AuthEngineFixture.Now.AddMinutes(20));

        var cache = new TokenCache(client, clock, TokenLifetimeConfig.Default);

        await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);

        // Within the 30-second skew of the 10-minute expiry, so still "fresh enough" to
        // renew but NOT yet expired.
        clock.Advance(TimeSpan.FromMinutes(10) - TimeSpan.FromSeconds(10));
        var renewed = await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);

        renewed.Get().Token.Should().Be("token-2");
        client.AcquireCount.Should().Be(2);
    }

    [Fact]
    public async Task Keeps_a_token_that_is_outside_the_renewal_skew()
    {
        var clock = AuthEngineFixture.Clock();
        var client = new FakeCredentialClient();
        client.ScriptToken(Resource, "token-1", AuthEngineFixture.Now.AddMinutes(10));

        var cache = new TokenCache(client, clock, TokenLifetimeConfig.Default);

        await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);
        clock.Advance(TimeSpan.FromMinutes(5));
        await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);

        client.AcquireCount.Should().Be(1);
    }

    [Fact]
    public async Task Caches_each_resource_independently()
    {
        var clock = AuthEngineFixture.Clock();
        var client = new FakeCredentialClient();
        client.ScriptToken(Resource, "token-a", AuthEngineFixture.Now.AddMinutes(10));
        client.ScriptToken("https://other.test.invalid", "token-b", AuthEngineFixture.Now.AddMinutes(10));

        var cache = new TokenCache(client, clock, TokenLifetimeConfig.Default);

        var first = await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);
        var second = await cache.GetAsync(
            "https://other.test.invalid",
            cancellationToken: TestContext.Current.CancellationToken);

        first.Get().Token.Should().Be("token-a");
        second.Get().Token.Should().Be("token-b");
        client.AcquireCount.Should().Be(2);
    }

    [Fact]
    public async Task Propagates_an_acquisition_failure_and_caches_nothing()
    {
        var clock = AuthEngineFixture.Clock();
        var client = new FakeCredentialClient();
        client.ScriptFailure(Resource, AuthProblems.InvalidClientCredentials());
        client.ScriptToken(Resource, "token-1", AuthEngineFixture.Now.AddMinutes(10));

        var cache = new TokenCache(client, clock, TokenLifetimeConfig.Default);

        var failed = await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);
        failed.IsFailure().Should().BeTrue();

        // A failure must not be cached, or a transient outage would be remembered.
        var recovered = await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);
        recovered.Get().Token.Should().Be("token-1");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public async Task Refuses_a_blank_resource(string? resource)
    {
        var cache = new TokenCache(
            new FakeCredentialClient(),
            AuthEngineFixture.Clock(),
            TokenLifetimeConfig.Default);

        var outcome = await cache.GetAsync(resource!, cancellationToken: TestContext.Current.CancellationToken);

        outcome.IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task Clear_drops_every_cached_token()
    {
        // After a revocation the cache must not keep serving, or a revoked session stays
        // usable until its tokens age out naturally.
        var clock = AuthEngineFixture.Clock();
        var client = new FakeCredentialClient();
        client.ScriptToken(Resource, "token-1", AuthEngineFixture.Now.AddMinutes(10));
        client.ScriptToken(Resource, "token-2", AuthEngineFixture.Now.AddMinutes(10));

        var cache = new TokenCache(client, clock, TokenLifetimeConfig.Default);

        await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);
        cache.Clear();
        var after = await cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken);

        after.Get().Token.Should().Be("token-2");
        client.AcquireCount.Should().Be(2);
    }

    [Fact]
    public async Task Collapses_a_concurrent_burst_into_one_acquisition()
    {
        // The waiters that queue behind the gate must find the token the winner cached
        // rather than each acquiring their own. A blocking client is used so every caller
        // is provably still queued when the first acquisition completes — without it the
        // burst can serialise and the re-check after the gate is never exercised.
        var clock = AuthEngineFixture.Clock();
        var release = new TaskCompletionSource();
        var client = new BlockingCredentialClient(
            release.Task,
            new TokenResponse("shared", AuthEngineFixture.Now.AddMinutes(10)));

        var cache = new TokenCache(client, clock, TokenLifetimeConfig.Default);

        var callers = Enumerable.Range(0, 8)
            .Select(_ => cache.GetAsync(Resource, cancellationToken: TestContext.Current.CancellationToken))
            .ToArray();

        await client.Entered;
        release.SetResult();

        var results = await Task.WhenAll(callers);

        results.Should().AllSatisfy(result => result.Get().Token.Should().Be("shared"));
        client.AcquireCount.Should().Be(1);
    }

    /// <summary>A client that parks inside the first acquisition until the test releases it.</summary>
    private sealed class BlockingCredentialClient(Task gate, TokenResponse response) : ICredentialClient
    {
        private readonly TaskCompletionSource _entered = new();

        public int AcquireCount { get; private set; }

        public Task Entered => this._entered.Task;

        public async Task<AtomiCloud.Diene.Results.Result<TokenResponse, AtomiCloud.Diene.Problems.IDomainProblem>>
            AcquireAsync(string resource, IReadOnlyList<string> scopes, CancellationToken cancellationToken)
        {
            this.AcquireCount++;
            this._entered.TrySetResult();
            await gate;
            return AtomiCloud.Diene.Results.Result
                .Ok<TokenResponse, AtomiCloud.Diene.Problems.IDomainProblem>(response);
        }

        public Task<AtomiCloud.Diene.Results.Result<RefreshedTokens, AtomiCloud.Diene.Problems.IDomainProblem>>
            RefreshAsync(string refreshToken, string resource, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<AtomiCloud.Diene.Results.Result<AtomiCloud.Diene.Results.Unit,
            AtomiCloud.Diene.Problems.IDomainProblem>>
            RevokeUserSessionsAsync(string userId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    [Fact]
    public async Task Passes_requested_scopes_through_to_acquisition()
    {
        var client = new FakeCredentialClient();
        var cache = new TokenCache(client, AuthEngineFixture.Clock(), TokenLifetimeConfig.Default);

        var outcome = await cache.GetAsync(
            Resource,
            ["notes:read"],
            TestContext.Current.CancellationToken);

        outcome.IsSuccess().Should().BeTrue();
        client.AcquireCount.Should().Be(1);
    }

    [Fact]
    public void Rejects_null_construction_arguments()
    {
        var client = new FakeCredentialClient();
        var clock = AuthEngineFixture.Clock();

        FluentActions.Invoking(() => new TokenCache(null!, clock, TokenLifetimeConfig.Default))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new TokenCache(client, null!, TokenLifetimeConfig.Default))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new TokenCache(client, clock, null!))
            .Should().Throw<ArgumentNullException>();
    }
}
