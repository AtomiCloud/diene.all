using AtomiCloud.Diene.AuthEngine;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Deferred;

public class DeferredTokenMinter_Exchange
{
    private const string Email = "Owner@Example.Invalid";

    [Fact]
    public async Task Claims_once_rechecks_the_user_and_consumes_before_returning()
    {
        var fixture = Fixture.Create("owner@example.invalid");
        var handoff = await fixture.Mint();

        var outcome = await fixture.Minter.Exchange(handoff.Nonce, TestContext.Current.CancellationToken);

        outcome.Get().Should().Be(new DeferredExchange("fake-one-time-token", "owner@example.invalid", 120));
        fixture.Management.UserLookups.Should().Equal(AuthEngineFixture.Subject);
        fixture.Management.MintedEmails.Should().Equal("owner@example.invalid");
        fixture.State(handoff).Should().Be(DeferredTokenState.Consumed);

        AssertExpired(await fixture.Minter.Exchange(handoff.Nonce, TestContext.Current.CancellationToken));
        fixture.Management.UserLookups.Should().ContainSingle();
        fixture.Management.MintedEmails.Should().ContainSingle();
    }

    [Fact]
    public async Task Allows_exactly_one_concurrent_claim()
    {
        var fixture = Fixture.Create(Email);
        var handoff = await fixture.Mint();

        var attempts = await Task.WhenAll(
            Enumerable.Range(0, 32)
                .Select(_ => fixture.Minter.Exchange(handoff.Nonce, TestContext.Current.CancellationToken)));

        attempts.Count(result => result.IsSuccess()).Should().Be(1);
        attempts.Count(result => result.IsFailure()).Should().Be(31);
        fixture.Management.UserLookups.Should().ContainSingle();
        fixture.Management.MintedEmails.Should().ContainSingle();
        fixture.State(handoff).Should().Be(DeferredTokenState.Consumed);
    }

    [Fact]
    public async Task A_claim_left_by_a_crash_is_fail_closed()
    {
        var fixture = Fixture.Create(Email);
        var handoff = await fixture.Mint();
        var digest = DeferredTokenMinter.Digest(handoff.Nonce);
        (await fixture.Store.Consume(digest, TestContext.Current.CancellationToken)).Get().IsSome().Should().BeTrue();

        AssertExpired(await fixture.Minter.Exchange(handoff.Nonce, TestContext.Current.CancellationToken));

        fixture.State(handoff).Should().Be(DeferredTokenState.Claimed);
        fixture.Management.UserLookups.Should().BeEmpty();
        fixture.Management.MintedEmails.Should().BeEmpty();
    }

    [Fact]
    public async Task Expiry_and_store_failure_are_the_same_external_problem()
    {
        var fixture = Fixture.Create(Email);
        var handoff = await fixture.Mint();
        fixture.Clock.Advance(TimeSpan.FromMinutes(15));

        AssertExpired(await fixture.Minter.Exchange(handoff.Nonce, TestContext.Current.CancellationToken));
        fixture.Management.UserLookups.Should().BeEmpty();

        var failed = Fixture.Create(Email);
        var failedHandoff = await failed.Mint();
        failed.Store.FailNextConsume(AuthProblems.IdentityProviderUnreachable());
        AssertExpired(await failed.Minter.Exchange(failedHandoff.Nonce, TestContext.Current.CancellationToken));
        failed.Management.UserLookups.Should().BeEmpty();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("short")]
    [InlineData("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")]
    public async Task Malformed_nonces_never_reach_the_store_or_provider(string? nonce)
    {
        var fixture = Fixture.Create(Email);

        AssertExpired(await fixture.Minter.Exchange(nonce!, TestContext.Current.CancellationToken));

        fixture.Store.Records.Should().BeEmpty();
        fixture.Management.UserLookups.Should().BeEmpty();
    }

    [Fact]
    public async Task Missing_suspended_null_email_and_rebound_users_are_revoked_identically()
    {
        await AssertRejectedUser(null);
        await AssertRejectedUser(new AuthManagementUser(AuthEngineFixture.Subject, Email, true));
        await AssertRejectedUser(new AuthManagementUser(AuthEngineFixture.Subject, null, false));
        await AssertRejectedUser(new AuthManagementUser(AuthEngineFixture.Subject, "other@example.invalid", false));
        await AssertRejectedUser(new AuthManagementUser(AuthEngineFixture.Subject, "Ä@example.invalid", false));
    }

    [Fact]
    public async Task User_lookup_and_provider_mint_failures_revoke_identically()
    {
        var lookup = Fixture.Create(Email);
        var lookupHandoff = await lookup.Mint();
        lookup.Management.FailNextGetUser(AuthProblems.IdentityProviderUnreachable());

        AssertExpired(await lookup.Minter.Exchange(lookupHandoff.Nonce, TestContext.Current.CancellationToken));
        lookup.State(lookupHandoff).Should().Be(DeferredTokenState.Revoked);
        lookup.Management.MintedEmails.Should().BeEmpty();

        var mint = Fixture.Create(Email);
        var mintHandoff = await mint.Mint();
        mint.Management.FailNextMint(AuthProblems.IdentityProviderUnreachable());

        AssertExpired(await mint.Minter.Exchange(mintHandoff.Nonce, TestContext.Current.CancellationToken));
        mint.State(mintHandoff).Should().Be(DeferredTokenState.Revoked);
        mint.Management.MintedEmails.Should().ContainSingle();
    }

    [Fact]
    public async Task A_blank_provider_token_is_revoked()
    {
        var fixture = Fixture.Create(Email);
        var handoff = await fixture.Mint();
        fixture.Management.OneTimeToken = "  ";

        AssertExpired(await fixture.Minter.Exchange(handoff.Nonce, TestContext.Current.CancellationToken));

        fixture.State(handoff).Should().Be(DeferredTokenState.Revoked);
    }

    [Fact]
    public async Task Settlement_failure_attempts_revocation_and_never_returns_the_token()
    {
        var fixture = Fixture.Create(Email);
        var handoff = await fixture.Mint();
        fixture.Store.FailNextSettle(AuthProblems.IdentityProviderUnreachable());

        AssertExpired(await fixture.Minter.Exchange(handoff.Nonce, TestContext.Current.CancellationToken));

        fixture.State(handoff).Should().Be(DeferredTokenState.Revoked);
        fixture.Management.MintedEmails.Should().ContainSingle();
    }

    [Fact]
    public async Task Failed_best_effort_revocation_leaves_the_exclusive_claim_in_place()
    {
        var fixture = Fixture.Create(Email);
        var handoff = await fixture.Mint();
        fixture.Management.FailNextGetUser(AuthProblems.IdentityProviderUnreachable());
        fixture.Store.FailNextSettle(AuthProblems.IdentityProviderUnreachable());

        AssertExpired(await fixture.Minter.Exchange(handoff.Nonce, TestContext.Current.CancellationToken));

        fixture.State(handoff).Should().Be(DeferredTokenState.Claimed);
        AssertExpired(await fixture.Minter.Exchange(handoff.Nonce, TestContext.Current.CancellationToken));
        fixture.Management.UserLookups.Should().ContainSingle();
    }

    [Fact]
    public async Task Email_comparison_is_ASCII_case_insensitive_only()
    {
        var ascii = Fixture.Create("oWNER@eXAMPLE.iNVALID");
        var handoff = await ascii.Mint();
        (await ascii.Minter.Exchange(handoff.Nonce, TestContext.Current.CancellationToken))
            .IsSuccess().Should().BeTrue();

        var lengthMismatch = Fixture.Create("x" + Email);
        var mismatchHandoff = await lengthMismatch.Mint();
        AssertExpired(await lengthMismatch.Minter.Exchange(
            mismatchHandoff.Nonce,
            TestContext.Current.CancellationToken));
    }

    private static async Task AssertRejectedUser(AuthManagementUser? user)
    {
        var fixture = Fixture.Create(user);
        var handoff = await fixture.Mint();

        AssertExpired(await fixture.Minter.Exchange(handoff.Nonce, TestContext.Current.CancellationToken));

        fixture.State(handoff).Should().Be(DeferredTokenState.Revoked);
        fixture.Management.UserLookups.Should().ContainSingle();
        fixture.Management.MintedEmails.Should().BeEmpty();
    }

    private static void AssertExpired(Result<DeferredExchange, IDomainProblem> outcome)
    {
        outcome.IsFailure(out var problem).Should().BeTrue();
        problem.Should().BeOfType<AppHandoffExpired>();
        problem!.Id.Should().Be("app_handoff_expired");
        problem.Title.Should().Be("App handoff expired");
        problem.Detail.Should().Be("This app handoff is expired or invalid.");
        problem.Version.Should().Be("v1");
    }

    private sealed record Fixture(
        FakeAuthClock Clock,
        InMemoryDeferredTokenStore Store,
        FakeAuthManagement Management,
        DeferredTokenMinter Minter)
    {
        internal static Fixture Create(string? currentEmail) =>
            Create(currentEmail is null
                ? null
                : new AuthManagementUser(AuthEngineFixture.Subject, currentEmail, false));

        internal static Fixture Create(AuthManagementUser? user)
        {
            var clock = AuthEngineFixture.Clock();
            var store = new InMemoryDeferredTokenStore(clock);
            var management = new FakeAuthManagement();
            if (user is not null) management.SetUser(user);
            return new Fixture(clock, store, management, new DeferredTokenMinter(store, management, clock));
        }

        internal async Task<DeferredHandoff> Mint() =>
            (await this.Minter.Mint(
                new DeferredPayload(AuthEngineFixture.Subject, Email),
                TestContext.Current.CancellationToken)).Get();

        internal DeferredTokenState State(DeferredHandoff handoff) =>
            this.Store.Records[DeferredTokenMinter.Digest(handoff.Nonce)].State;
    }
}
