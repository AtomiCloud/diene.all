using AtomiCloud.Diene.ApiEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ApiEngine.Transport;
using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Transport;

/// <summary>
/// Per-backend token attachment, driven through auth-engine's own published credential fake.
/// </summary>
public class AtomiAuthHandler_SendAsync
{
    private const string NotesResource = "https://notes.test.invalid";
    private const string ArchiveResource = "https://archive.test.invalid";

    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Attaches_a_bearer_token_for_its_own_resource()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondOk("{}");
        var tokens = FakeTokens.Cache(NotesResource);

        using var http = Client(upstream, tokens, NotesResource);
        using var response = await http.GetAsync("/notes/1", Ct);

        upstream.Requests[0].Authorization.Should().Be($"Bearer {FakeTokens.TokenFor(NotesResource)}");
    }

    [Fact]
    public async Task Two_handlers_carry_two_different_tokens_and_neither_sees_the_other()
    {
        var notes = new FakeUpstream("notes");
        var archive = new FakeUpstream("archive");
        notes.RespondOk("{}");
        archive.RespondOk("{}");
        var tokens = FakeTokens.Cache(NotesResource, ArchiveResource);

        using var notesClient = Client(notes, tokens, NotesResource);
        using var archiveClient = Client(archive, tokens, ArchiveResource);
        using var first = await notesClient.GetAsync("/notes/1", Ct);
        using var second = await archiveClient.GetAsync("/archive/1", Ct);

        // The resource is fixed at construction, so there is no code path along which one upstream's
        // credential could be sent to another. A shared handler taking a resource per call would make
        // that mistake representable; this shape does not.
        notes.Requests[0].Authorization.Should().Be($"Bearer {FakeTokens.TokenFor(NotesResource)}");
        archive.Requests[0].Authorization.Should().Be($"Bearer {FakeTokens.TokenFor(ArchiveResource)}");
    }

    [Fact]
    public async Task Reuses_a_cached_token_across_calls_rather_than_acquiring_per_request()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondOk("{}");
        upstream.RespondOk("{}");
        var credentials = new FakeCredentialClient();
        var clock = new FakeAuthClock();
        credentials.ScriptToken(NotesResource, "token-1", clock.UtcNow.AddHours(1));

        using var http = Client(upstream, FakeTokens.Cache(credentials, clock), NotesResource);
        using var first = await http.GetAsync("/notes/1", Ct);
        using var second = await http.GetAsync("/notes/2", Ct);

        // Counted, not inferred: acquiring per request is invisible in the headers, which look
        // identical either way, and it is the property that makes an IdP the bottleneck under load.
        credentials.AcquireCount.Should().Be(1);
    }

    [Fact]
    public async Task Throws_the_typed_problem_rather_than_calling_unauthenticated()
    {
        var upstream = new FakeUpstream("notes");
        var credentials = new FakeCredentialClient();
        credentials.ScriptFailure(NotesResource, new Unauthenticated("The IdP refused the client."));

        using var http = Client(upstream, FakeTokens.Cache(credentials, new FakeAuthClock()), NotesResource);
        var call = async () => await http.GetAsync("/notes/1", Ct);

        var thrown = await call.Should().ThrowAsync<DomainProblemException>();
        thrown.Which.Problem.Should().BeOfType<Unauthenticated>();

        // The request must not have been made. Sending it anonymously would turn an auth failure into
        // whatever the upstream says about anonymous callers, which is a different problem entirely.
        upstream.Attempts.Should().Be(0);
    }

    [Fact]
    public void Rejects_construction_without_a_token_source_resource_or_scopes()
    {
        var tokens = FakeTokens.Cache(NotesResource);

        var noTokens = () => new AtomiAuthHandler(null!, NotesResource, []);
        var noResource = () => new AtomiAuthHandler(tokens, "  ", []);
        var noScopes = () => new AtomiAuthHandler(tokens, NotesResource, null!);

        noTokens.Should().Throw<ArgumentNullException>();
        noResource.Should().Throw<ArgumentException>();
        noScopes.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task Rejects_a_null_request()
    {
        var handler = new AtomiAuthHandler(FakeTokens.Cache(NotesResource), NotesResource, [])
        {
            InnerHandler = new FakeUpstream("notes"),
        };
        using var invoker = new HttpMessageInvoker(handler);

        var send = () => invoker.SendAsync(null!, Ct);
        await send.Should().ThrowAsync<ArgumentNullException>();
    }

    private static HttpClient Client(FakeUpstream upstream, TokenCache tokens, string resource) =>
        new(new AtomiAuthHandler(tokens, resource, ["notes:read"]) { InnerHandler = upstream })
        {
            BaseAddress = new Uri(ApiEngineFixture.BaseAddress),
        };
}
