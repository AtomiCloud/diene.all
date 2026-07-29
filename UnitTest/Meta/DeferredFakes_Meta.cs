using AtomiCloud.Diene.AuthEngine;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Meta;

public class DeferredFakes_Meta
{
    [Fact]
    public async Task InMemory_store_models_create_atomic_claim_and_terminal_settlement()
    {
        var clock = AuthEngineFixture.Clock();
        var store = new InMemoryDeferredTokenStore(clock);
        var payload = new DeferredPayload("user-1", "owner@example.invalid");

        (await store.Put("digest", payload, TimeSpan.FromMinutes(15), TestContext.Current.CancellationToken))
            .IsSuccess().Should().BeTrue();
        var snapshot = store.Records;
        snapshot["digest"].Should().Be(new DeferredStoreSnapshot(
            payload,
            AuthEngineFixture.Now.AddMinutes(15),
            TimeSpan.FromMinutes(15),
            DeferredTokenState.Active));

        var claims = await Task.WhenAll(
            Enumerable.Range(0, 16)
                .Select(_ => store.Consume("digest", TestContext.Current.CancellationToken)));
        claims.Count(result => result.Get().IsSome()).Should().Be(1);
        store.Records["digest"].State.Should().Be(DeferredTokenState.Claimed);

        (await store.Settle(
            "digest",
            DeferredTokenState.Consumed,
            TestContext.Current.CancellationToken)).IsSuccess().Should().BeTrue();
        store.Records["digest"].State.Should().Be(DeferredTokenState.Consumed);

        // Records is a defensive snapshot: mutating the fake afterwards cannot rewrite
        // a previously captured assertion view.
        snapshot["digest"].State.Should().Be(DeferredTokenState.Active);
    }

    [Fact]
    public async Task InMemory_store_rejects_impossible_records_and_transitions()
    {
        var store = new InMemoryDeferredTokenStore(AuthEngineFixture.Clock());
        var payload = new DeferredPayload("user-1", "owner@example.invalid");
        var cancellationToken = TestContext.Current.CancellationToken;

        (await store.Put("", payload, TimeSpan.FromMinutes(1), cancellationToken))
            .IsFailure().Should().BeTrue();
        (await store.Put("a", null!, TimeSpan.FromMinutes(1), cancellationToken))
            .IsFailure().Should().BeTrue();
        (await store.Put("a", payload, TimeSpan.Zero, cancellationToken))
            .IsFailure().Should().BeTrue();
        (await store.Put("a", payload, TimeSpan.FromMinutes(1), cancellationToken))
            .IsSuccess().Should().BeTrue();
        (await store.Put("a", payload, TimeSpan.FromMinutes(1), cancellationToken))
            .IsFailure().Should().BeTrue();
        (await store.Consume("missing", cancellationToken)).Get().IsNone().Should().BeTrue();
        (await store.Settle("missing", DeferredTokenState.Consumed, cancellationToken))
            .IsFailure().Should().BeTrue();
        (await store.Settle("a", DeferredTokenState.Active, cancellationToken))
            .IsFailure().Should().BeTrue();
        (await store.Settle("a", DeferredTokenState.Revoked, cancellationToken))
            .IsFailure().Should().BeTrue();

        (await store.Consume("a", cancellationToken)).Get().IsSome().Should().BeTrue();
        (await store.Settle("a", DeferredTokenState.Revoked, cancellationToken))
            .IsSuccess().Should().BeTrue();
        store.Records["a"].State.Should().Be(DeferredTokenState.Revoked);
    }

    [Fact]
    public async Task InMemory_store_honours_expiry_and_each_scripted_failure_queue()
    {
        var clock = AuthEngineFixture.Clock();
        var store = new InMemoryDeferredTokenStore(clock);
        var payload = new DeferredPayload("user-1", "owner@example.invalid");
        var cancellationToken = TestContext.Current.CancellationToken;

        store.FailNextPut(AuthProblems.IdentityProviderUnreachable());
        (await store.Put("put", payload, TimeSpan.FromMinutes(1), cancellationToken))
            .IsFailure().Should().BeTrue();

        await store.Put("consume", payload, TimeSpan.FromMinutes(1), cancellationToken);
        store.FailNextConsume(AuthProblems.IdentityProviderUnreachable());
        (await store.Consume("consume", cancellationToken)).IsFailure().Should().BeTrue();
        (await store.Consume("consume", cancellationToken)).Get().IsSome().Should().BeTrue();

        store.FailNextSettle(AuthProblems.IdentityProviderUnreachable());
        (await store.Settle("consume", DeferredTokenState.Consumed, cancellationToken))
            .IsFailure().Should().BeTrue();
        (await store.Settle("consume", DeferredTokenState.Consumed, cancellationToken))
            .IsSuccess().Should().BeTrue();

        await store.Put("expired", payload, TimeSpan.FromSeconds(1), cancellationToken);
        clock.Advance(TimeSpan.FromSeconds(1));
        (await store.Consume("expired", cancellationToken)).Get().IsNone().Should().BeTrue();

        FluentActions.Invoking(() => store.FailNextPut(null!)).Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => store.FailNextConsume(null!)).Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => store.FailNextSettle(null!)).Should().Throw<ArgumentNullException>();

        // The parameterless fake uses its own stable FakeAuthClock and remains usable.
        var defaulted = new InMemoryDeferredTokenStore();
        (await defaulted.Put("default", payload, TimeSpan.FromMinutes(1), cancellationToken))
            .IsSuccess().Should().BeTrue();
    }

    [Fact]
    public async Task Fake_management_models_users_tokens_claims_roles_and_deletion()
    {
        var fake = new FakeAuthManagement { OneTimeToken = "ott-9" };
        var user = new AuthManagementUser("user-1", "owner@example.invalid", false);
        fake.SetUser(user);
        var cancellationToken = TestContext.Current.CancellationToken;

        (await fake.GetUser("user-1", cancellationToken)).Get().Get().Should().Be(user);
        (await fake.GetUser("missing", cancellationToken)).Get().IsNone().Should().BeTrue();
        (await fake.MintOneTimeToken("owner@example.invalid", cancellationToken)).Get().Should().Be("ott-9");
        (await fake.SetClaim("user-1", "home", "lapras", cancellationToken)).IsSuccess().Should().BeTrue();
        fake.Claims[("user-1", "home")].Should().Be("lapras");
        (await fake.RemoveClaim("user-1", "home", cancellationToken)).IsSuccess().Should().BeTrue();
        fake.Claims.Should().BeEmpty();
        (await fake.AssignRole("user-1", "admin", cancellationToken)).IsSuccess().Should().BeTrue();
        (await fake.RemoveRole("user-1", "admin", cancellationToken)).IsSuccess().Should().BeTrue();
        (await fake.DeleteUser("user-1", cancellationToken)).IsSuccess().Should().BeTrue();

        fake.UserLookups.Should().Equal("user-1", "missing");
        fake.MintedEmails.Should().Equal("owner@example.invalid");
        fake.AssignedRoles.Should().Equal(("user-1", "admin"));
        fake.RemovedRoles.Should().Equal(("user-1", "admin"));
        fake.DeletedUsers.Should().Equal("user-1");
        (await fake.GetUser("user-1", cancellationToken)).Get().IsNone().Should().BeTrue();
    }

    [Fact]
    public async Task Fake_management_rejects_invalid_inputs_and_null_scripts()
    {
        var fake = new FakeAuthManagement();
        var cancellationToken = TestContext.Current.CancellationToken;

        FluentActions.Invoking(() => fake.SetUser(null!)).Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => fake.SetUser(new AuthManagementUser(" ", null, false)))
            .Should().Throw<ArgumentException>();
        FluentActions.Invoking(() => fake.FailNext(null!)).Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => fake.FailNextGetUser(null!)).Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => fake.FailNextMint(null!)).Should().Throw<ArgumentNullException>();

        (await fake.GetUser(" ", cancellationToken)).IsFailure().Should().BeTrue();
        (await fake.MintOneTimeToken("", cancellationToken)).IsFailure().Should().BeTrue();
        (await fake.SetClaim("", "key", "value", cancellationToken)).IsFailure().Should().BeTrue();
        (await fake.SetClaim("user", "key", " ", cancellationToken)).IsFailure().Should().BeTrue();
        (await fake.RemoveClaim("user", "", cancellationToken)).IsFailure().Should().BeTrue();
        (await fake.AssignRole("", "role", cancellationToken)).IsFailure().Should().BeTrue();
        (await fake.RemoveRole("user", "", cancellationToken)).IsFailure().Should().BeTrue();
        (await fake.DeleteUser("", cancellationToken)).IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task Fake_management_can_fail_every_operation_without_recording_success()
    {
        var fake = new FakeAuthManagement();
        fake.SetUser(new AuthManagementUser("user-1", "owner@example.invalid", false));
        var cancellationToken = TestContext.Current.CancellationToken;

        fake.FailNextGetUser(AuthProblems.IdentityProviderUnreachable());
        (await fake.GetUser("user-1", cancellationToken)).IsFailure().Should().BeTrue();
        fake.FailNextMint(AuthProblems.IdentityProviderUnreachable());
        (await fake.MintOneTimeToken("owner@example.invalid", cancellationToken))
            .IsFailure().Should().BeTrue();

        fake.FailNext(AuthProblems.IdentityProviderUnreachable());
        (await fake.SetClaim("user-1", "key", "value", cancellationToken))
            .IsFailure().Should().BeTrue();
        fake.FailNext(AuthProblems.IdentityProviderUnreachable());
        (await fake.RemoveClaim("user-1", "key", cancellationToken)).IsFailure().Should().BeTrue();
        fake.FailNext(AuthProblems.IdentityProviderUnreachable());
        (await fake.AssignRole("user-1", "role", cancellationToken)).IsFailure().Should().BeTrue();
        fake.FailNext(AuthProblems.IdentityProviderUnreachable());
        (await fake.RemoveRole("user-1", "role", cancellationToken)).IsFailure().Should().BeTrue();
        fake.FailNext(AuthProblems.IdentityProviderUnreachable());
        (await fake.DeleteUser("user-1", cancellationToken)).IsFailure().Should().BeTrue();

        fake.Claims.Should().BeEmpty();
        fake.AssignedRoles.Should().BeEmpty();
        fake.RemovedRoles.Should().BeEmpty();
        fake.DeletedUsers.Should().BeEmpty();
    }
}
