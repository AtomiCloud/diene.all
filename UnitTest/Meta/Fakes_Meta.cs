using System.Net;
using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Meta;

/// <summary>
/// Meta tier over the shipped fakes: every behaviour a consumer will rely on is proven,
/// including the guards that make a fake refuse to model a state the real system cannot
/// be in.
/// </summary>
public class Fakes_Meta
{
    private const string Resource = "https://api.test.invalid";

    [Fact]
    public void FakeAuthClock_starts_at_a_stable_default_and_can_be_driven()
    {
        var clock = new FakeAuthClock();
        clock.UtcNow.Should().Be(FakeAuthClock.DefaultInstant);

        clock.Advance(TimeSpan.FromMinutes(5));
        clock.UtcNow.Should().Be(FakeAuthClock.DefaultInstant.AddMinutes(5));

        clock.Set(AuthEngineFixture.Now);
        clock.UtcNow.Should().Be(AuthEngineFixture.Now);
    }

    [Fact]
    public async Task FakeCredentialClient_serves_its_default_when_nothing_is_scripted()
    {
        var client = new FakeCredentialClient();

        var outcome = await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken);

        outcome.Get().Token.Should().Be("fake-access-token");
        client.AcquireCount.Should().Be(1);
    }

    [Fact]
    public async Task FakeCredentialClient_consumes_scripted_responses_in_order()
    {
        // Ordering is how a test expresses "the first call succeeds and the renewal
        // fails" without a mocking framework, so it is asserted rather than assumed.
        var client = new FakeCredentialClient();
        client.ScriptToken(Resource, "first", AuthEngineFixture.Now.AddMinutes(10));
        client.ScriptFailure(Resource, AuthProblems.ExpiredToken());

        (await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken))
            .Get().Token.Should().Be("first");
        (await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();

        // Exhausted queue falls back to the default rather than throwing.
        (await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken))
            .Get().Token.Should().Be("fake-access-token");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("  ")]
    public async Task FakeCredentialClient_refuses_a_blank_resource(string? resource)
    {
        var client = new FakeCredentialClient();

        var outcome = await client.AcquireAsync(resource!, [], TestContext.Current.CancellationToken);

        outcome.IsFailure().Should().BeTrue();
    }

    [Fact]
    public void FakeCredentialClient_rejects_a_blank_scripted_resource() =>
        FluentActions.Invoking(() => new FakeCredentialClient().ScriptToken(" ", "t", DateTimeOffset.MaxValue))
            .Should().Throw<ArgumentException>();

    [Fact]
    public async Task FakeCredentialClient_returns_the_rotated_refresh_token()
    {
        var client = new FakeCredentialClient { RotatedRefreshToken = "rt-9" };
        client.ScriptToken(Resource, "at-9", AuthEngineFixture.Now.AddMinutes(10));

        var outcome = await client.RefreshAsync("rt-1", Resource, TestContext.Current.CancellationToken);

        outcome.Get().RefreshToken.Should().Be("rt-9");
        outcome.Get().Access.Token.Should().Be("at-9");
        client.RefreshCount.Should().Be(1);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("   ")]
    public async Task FakeCredentialClient_refuses_a_blank_refresh_token(string? token)
    {
        var client = new FakeCredentialClient();

        var outcome = await client.RefreshAsync(token!, Resource, TestContext.Current.CancellationToken);

        outcome.IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task FakeCredentialClient_propagates_a_scripted_refresh_failure()
    {
        var client = new FakeCredentialClient();
        client.ScriptFailure(Resource, AuthProblems.ExpiredToken());

        var outcome = await client.RefreshAsync("rt-1", Resource, TestContext.Current.CancellationToken);

        outcome.IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task FakeCredentialClient_records_revoked_users_only_on_success()
    {
        var client = new FakeCredentialClient();

        (await client.RevokeUserSessionsAsync("user-1", TestContext.Current.CancellationToken))
            .IsSuccess().Should().BeTrue();
        client.RevokedUsers.Should().BeEquivalentTo(["user-1"]);

        // A failed revocation must not be recorded, or a test would assert a session was
        // revoked when the call was refused.
        client.RevokeOutcome = Result.Err<Unit, IDomainProblem>(AuthProblems.InvalidClientCredentials());
        (await client.RevokeUserSessionsAsync("user-2", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();
        client.RevokedUsers.Should().BeEquivalentTo(["user-1"]);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("  ")]
    public async Task FakeCredentialClient_refuses_a_blank_user_id(string? userId)
    {
        var client = new FakeCredentialClient();

        var outcome = await client.RevokeUserSessionsAsync(userId!, TestContext.Current.CancellationToken);

        outcome.IsFailure().Should().BeTrue();
        client.RevokedUsers.Should().BeEmpty();
    }

    [Fact]
    public void FakeOnboardingBackend_rejects_a_blank_identifier()
    {
        FluentActions.Invoking(() => new FakeOnboardingBackend(" ")).Should().Throw<ArgumentException>();
        FluentActions.Invoking(() => new FakeOnboardingBackend().WithKnownUser("  "))
            .Should().Throw<ArgumentException>();

        new FakeOnboardingBackend("custom").BackendId.Should().Be("custom");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("  ")]
    public async Task FakeOnboardingBackend_refuses_a_blank_subject(string? subject)
    {
        var backend = new FakeOnboardingBackend();

        (await backend.HasUserAsync(subject!, TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();
        (await backend.WriteHomeLandscapeAsync(subject!, "lapras", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task FakeOnboardingBackend_marks_a_written_subject_as_known()
    {
        // Mirrors the real backend after OnboardSync: writing the claim creates the user
        // record. A fake that recorded one without the other would let a test pass
        // against a state the real system cannot reach.
        var backend = new FakeOnboardingBackend();

        (await backend.HasUserAsync("user-1", TestContext.Current.CancellationToken))
            .Get().Should().BeFalse();

        await backend.WriteHomeLandscapeAsync("user-1", "lapras", TestContext.Current.CancellationToken);

        (await backend.HasUserAsync("user-1", TestContext.Current.CancellationToken))
            .Get().Should().BeTrue();
        backend.WrittenLandscapes["user-1"].Should().Be("lapras");
    }

    [Fact]
    public async Task StubHttpMessageHandler_refuses_an_unexpected_extra_call()
    {
        // An exhausted queue is a test-authoring error. Returning a default response
        // would let an unexpected extra request pass unnoticed.
        var handler = new StubHttpMessageHandler();
        handler.RespondStatus(HttpStatusCode.OK);
        using var http = new HttpClient(handler);

        await http.GetAsync(new Uri("https://x.test.invalid"), TestContext.Current.CancellationToken);

        await FluentActions
            .Awaiting(() => http.GetAsync(new Uri("https://x.test.invalid"), TestContext.Current.CancellationToken))
            .Should().ThrowAsync<InvalidOperationException>()
            .WithMessage("*No stubbed response remains*");
    }

    [Fact]
    public async Task StubHttpMessageHandler_captures_requests_and_bodies()
    {
        var handler = new StubHttpMessageHandler();
        handler.RespondStatus(HttpStatusCode.OK);
        handler.RespondStatus(HttpStatusCode.OK);
        using var http = new HttpClient(handler);

        await http.GetAsync(new Uri("https://x.test.invalid/a"), TestContext.Current.CancellationToken);
        await http.PostAsync(
            new Uri("https://x.test.invalid/b"),
            new StringContent("hello"),
            TestContext.Current.CancellationToken);

        handler.Requests.Should().HaveCount(2);
        handler.CapturedBodies.Should().BeEquivalentTo(["", "hello"], options => options.WithStrictOrdering());
    }

    [Fact]
    public void StubHttpMessageHandler_rejects_a_null_responder() =>
        FluentActions.Invoking(() => new StubHttpMessageHandler().Respond(null!))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void FakeSigningKeyResolver_rejects_a_null_key_array() =>
        FluentActions.Invoking(() => new FakeSigningKeyResolver(null!))
            .Should().Throw<ArgumentNullException>();
}
