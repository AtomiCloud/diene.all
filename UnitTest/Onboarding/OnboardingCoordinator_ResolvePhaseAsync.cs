using AtomiCloud.Diene.AuthEngine.Onboarding;
using AtomiCloud.Diene.AuthEngine.TestHelper.Assertions;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Onboarding;

public class OnboardingCoordinator_ResolvePhaseAsync
{
    private static async Task<AuthClaims> ClaimsWith(string? homeLandscape)
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var validator = AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock());

        var extra = homeLandscape is null
            ? null
            : new Dictionary<string, object> { ["home_landscape"] = homeLandscape };

        var token = issuer.MintValidFor(
            AuthEngineFixture.Subject,
            AuthEngineFixture.Audience,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            extraClaims: extra);

        return (await validator.ValidateAsync(
            token,
            AuthEngineFixture.Audience,
            TestContext.Current.CancellationToken)).ShouldBeAuthorized();
    }

    [Fact]
    public async Task Reports_complete_when_the_claim_is_present()
    {
        var claims = await ClaimsWith("lapras");
        var backend = new FakeOnboardingBackend();
        var coordinator = new OnboardingCoordinator(AuthEngineFixture.Config(), backend);

        var phase = await coordinator.ResolvePhaseAsync(claims, TestContext.Current.CancellationToken);

        phase.Get().Should().Be(OnboardingPhase.Complete);
    }

    [Fact]
    public async Task Does_not_consult_the_backend_when_the_claim_is_present()
    {
        // Claims-first: the common path must cost no backend round trip. A backend
        // rigged to fail proves the call never happened.
        var claims = await ClaimsWith("lapras");
        var backend = new FakeOnboardingBackend { ProbeFailure = AuthProblems.IdentityProviderUnreachable() };
        var coordinator = new OnboardingCoordinator(AuthEngineFixture.Config(), backend);

        var phase = await coordinator.ResolvePhaseAsync(claims, TestContext.Current.CancellationToken);

        phase.Get().Should().Be(OnboardingPhase.Complete);
    }

    [Fact]
    public async Task Reports_select_landscape_for_a_user_the_backend_does_not_know()
    {
        var claims = await ClaimsWith(null);
        var coordinator = new OnboardingCoordinator(AuthEngineFixture.Config(), new FakeOnboardingBackend());

        var phase = await coordinator.ResolvePhaseAsync(claims, TestContext.Current.CancellationToken);

        phase.Get().Should().Be(OnboardingPhase.SelectLandscape);
    }

    [Fact]
    public async Task Reports_awaiting_sync_for_a_known_user_without_a_claim()
    {
        // A backend record but no claim means the pick landed and the sync has not.
        // Reporting SelectLandscape here would re-show the selector to a user who
        // already chose.
        var claims = await ClaimsWith(null);
        var backend = new FakeOnboardingBackend().WithKnownUser(AuthEngineFixture.Subject);
        var coordinator = new OnboardingCoordinator(AuthEngineFixture.Config(), backend);

        var phase = await coordinator.ResolvePhaseAsync(claims, TestContext.Current.CancellationToken);

        phase.Get().Should().Be(OnboardingPhase.AwaitingSync);
    }

    [Fact]
    public async Task Propagates_a_backend_probe_failure()
    {
        var claims = await ClaimsWith(null);
        var backend = new FakeOnboardingBackend { ProbeFailure = AuthProblems.IdentityProviderUnreachable() };
        var coordinator = new OnboardingCoordinator(AuthEngineFixture.Config(), backend);

        var phase = await coordinator.ResolvePhaseAsync(claims, TestContext.Current.CancellationToken);

        phase.GetFailure().Detail.Should().Contain("could not be reached");
    }

    [Fact]
    public async Task CompleteAsync_writes_the_picked_landscape()
    {
        var claims = await ClaimsWith(null);
        var backend = new FakeOnboardingBackend();
        var coordinator = new OnboardingCoordinator(AuthEngineFixture.Config(), backend);

        var outcome = await coordinator.CompleteAsync(claims, " lapras ", TestContext.Current.CancellationToken);

        outcome.IsSuccess().Should().BeTrue();
        backend.WrittenLandscapes[AuthEngineFixture.Subject].Should().Be("lapras");
    }

    [Fact]
    public async Task CompleteAsync_moves_the_user_to_awaiting_sync_until_the_claim_is_reissued()
    {
        // The claim lives in the TOKEN, so a user who has just completed onboarding stays
        // at AwaitingSync until a fresh token carries it. Reporting Complete off the
        // backend write would contradict what the next request's token actually says.
        var claims = await ClaimsWith(null);
        var backend = new FakeOnboardingBackend();
        var coordinator = new OnboardingCoordinator(AuthEngineFixture.Config(), backend);

        await coordinator.CompleteAsync(claims, "lapras", TestContext.Current.CancellationToken);
        var phase = await coordinator.ResolvePhaseAsync(claims, TestContext.Current.CancellationToken);

        phase.Get().Should().Be(OnboardingPhase.AwaitingSync);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task CompleteAsync_refuses_a_blank_landscape(string? landscape)
    {
        var claims = await ClaimsWith(null);
        var coordinator = new OnboardingCoordinator(AuthEngineFixture.Config(), new FakeOnboardingBackend());

        var outcome = await coordinator.CompleteAsync(claims, landscape!, TestContext.Current.CancellationToken);

        outcome.IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task CompleteAsync_propagates_a_write_failure()
    {
        var claims = await ClaimsWith(null);
        var backend = new FakeOnboardingBackend { WriteFailure = AuthProblems.IdentityProviderUnreachable() };
        var coordinator = new OnboardingCoordinator(AuthEngineFixture.Config(), backend);

        var outcome = await coordinator.CompleteAsync(claims, "lapras", TestContext.Current.CancellationToken);

        outcome.IsFailure().Should().BeTrue();
        backend.WrittenLandscapes.Should().BeEmpty();
    }

    [Fact]
    public void Rejects_null_construction_arguments()
    {
        FluentActions.Invoking(() => new OnboardingCoordinator(null!, new FakeOnboardingBackend()))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new OnboardingCoordinator(AuthEngineFixture.Config(), null!))
            .Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task Rejects_null_claims()
    {
        var coordinator = new OnboardingCoordinator(AuthEngineFixture.Config(), new FakeOnboardingBackend());

        await FluentActions
            .Awaiting(() => coordinator.ResolvePhaseAsync(null!, TestContext.Current.CancellationToken))
            .Should().ThrowAsync<ArgumentNullException>();
        await FluentActions
            .Awaiting(() => coordinator.CompleteAsync(null!, "lapras", TestContext.Current.CancellationToken))
            .Should().ThrowAsync<ArgumentNullException>();
    }
}
