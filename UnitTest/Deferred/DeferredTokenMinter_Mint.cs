using AtomiCloud.Diene.AuthEngine;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Deferred;

public class DeferredTokenMinter_Mint
{
    [Fact]
    public async Task Mints_32_random_bytes_as_base64url_and_stores_only_the_digest()
    {
        var clock = AuthEngineFixture.Clock();
        var store = new InMemoryDeferredTokenStore(clock);
        var minter = new DeferredTokenMinter(store, new FakeAuthManagement(), clock);

        var first = (await minter.Mint(
            new DeferredPayload(" user-1 ", " Owner@Example.Invalid "),
            TestContext.Current.CancellationToken)).Get();
        var second = (await minter.Mint(
            new DeferredPayload("user-1", "owner@example.invalid"),
            TestContext.Current.CancellationToken)).Get();

        first.Nonce.Should().HaveLength(43).And.MatchRegex("^[A-Za-z0-9_-]{43}$");
        second.Nonce.Should().NotBe(first.Nonce);
        first.ExpiresAt.Should().Be(AuthEngineFixture.Now.AddMinutes(15));

        var digest = DeferredTokenMinter.Digest(first.Nonce);
        digest.Should().HaveLength(64).And.MatchRegex("^[0-9a-f]{64}$");
        store.Records.Keys.Should().Contain(digest).And.NotContain(first.Nonce);
        store.Records[digest].Should().BeEquivalentTo(new
        {
            Payload = new DeferredPayload("user-1", "Owner@Example.Invalid"),
            ExpiresAt = AuthEngineFixture.Now.AddMinutes(15),
            Ttl = TimeSpan.FromMinutes(15),
            State = DeferredTokenState.Active,
        });
    }

    [Theory]
    [InlineData(null, "owner@example.invalid")]
    [InlineData("", "owner@example.invalid")]
    [InlineData("user-1", null)]
    [InlineData("user-1", "   ")]
    public async Task Rejects_a_payload_without_a_validated_subject_and_email(string? subject, string? email)
    {
        var clock = AuthEngineFixture.Clock();
        var store = new InMemoryDeferredTokenStore(clock);
        var minter = new DeferredTokenMinter(store, new FakeAuthManagement(), clock);

        var outcome = await minter.Mint(
            new DeferredPayload(subject!, email!),
            TestContext.Current.CancellationToken);

        outcome.IsFailure(out var problem).Should().BeTrue();
        problem!.Id.Should().Be("unauthenticated");
        store.Records.Should().BeEmpty();
    }

    [Fact]
    public async Task Rejects_a_null_payload()
    {
        var clock = AuthEngineFixture.Clock();
        var minter = new DeferredTokenMinter(
            new InMemoryDeferredTokenStore(clock),
            new FakeAuthManagement(),
            clock);

        (await minter.Mint(null!, TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task Propagates_a_mint_store_failure()
    {
        var clock = AuthEngineFixture.Clock();
        var store = new InMemoryDeferredTokenStore(clock);
        store.FailNextPut(AuthProblems.IdentityProviderUnreachable());
        var minter = new DeferredTokenMinter(store, new FakeAuthManagement(), clock);

        var outcome = await minter.Mint(
            new DeferredPayload("user-1", "owner@example.invalid"),
            TestContext.Current.CancellationToken);

        outcome.IsFailure(out var problem).Should().BeTrue();
        problem!.Detail.Should().Contain("could not be reached");
    }

    [Fact]
    public void Constructor_and_digest_reject_null_dependencies()
    {
        var clock = AuthEngineFixture.Clock();
        var store = new InMemoryDeferredTokenStore(clock);
        var management = new FakeAuthManagement();

        FluentActions.Invoking(() => new DeferredTokenMinter(null!, management, clock))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new DeferredTokenMinter(store, null!, clock))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new DeferredTokenMinter(store, management, null!))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => DeferredTokenMinter.Digest(null!))
            .Should().Throw<ArgumentNullException>();
    }
}
