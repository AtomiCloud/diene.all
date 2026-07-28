using System.Net;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.ApiEngine.Calls;
using AtomiCloud.Diene.ApiEngine.Client;
using AtomiCloud.Diene.ApiEngine.TestHelper.Builders;
using AtomiCloud.Diene.ApiEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ApiEngine.Transport;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Meta;

/// <summary>
/// Contract parity for the shipped fakes: each one is proven to behave like the thing it stands in
/// for, and the fixtures are proven to produce bodies the real classifier accepts.
/// </summary>
/// <remarks>
/// A fake that drifts from its contract is worse than no fake: it makes a consumer's suite green about
/// a behaviour the real pipeline does not have. So the fakes are exercised THROUGH the real handlers
/// and the real classifier here, never merely inspected.
/// </remarks>
public class Fakes_Meta
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task The_fake_upstream_serves_its_queue_in_order_and_records_what_it_received()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondOk("{\"first\":1}");
        upstream.RespondJson(HttpStatusCode.BadRequest, "{\"second\":2}");

        using var http = new HttpClient(upstream) { BaseAddress = new Uri(ApiEngineFixture.BaseAddress) };
        using var first = await http.PostAsync("/notes", new StringContent("body-1"), Ct);
        using var second = await http.GetAsync("/notes/2", Ct);

        first.StatusCode.Should().Be(HttpStatusCode.OK);
        second.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        upstream.Name.Should().Be("notes");
        upstream.Attempts.Should().Be(2);
        upstream.Requests[0].Method.Should().Be(HttpMethod.Post);
        upstream.Requests[0].Body.Should().Be("body-1");
        upstream.Requests[1].Body.Should().BeEmpty("a GET carries no body");
        upstream.Requests[1].Authorization.Should().BeNull();
    }

    [Fact]
    public async Task The_fake_upstream_fails_loudly_when_its_queue_is_exhausted()
    {
        var upstream = new FakeUpstream("notes");

        using var http = new HttpClient(upstream) { BaseAddress = new Uri(ApiEngineFixture.BaseAddress) };
        var call = async () => await http.GetAsync("/notes/1", Ct);

        // An unexpected extra call is precisely the retry defect this fake exists to catch, so a
        // default response here would disarm the assertion that matters most.
        await call.Should().ThrowAsync<InvalidOperationException>().WithMessage("*no stubbed response*");
    }

    [Fact]
    public async Task The_fake_upstreams_network_failure_is_the_one_condition_the_engine_retries()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondNetworkFailure();
        upstream.RespondOk("{}");

        using var http = new HttpClient(new RetryOnceHandler { InnerHandler = upstream })
        {
            BaseAddress = new Uri(ApiEngineFixture.BaseAddress),
        };
        using var response = await http.GetAsync("/notes/1", Ct);

        // Parity with the real thing: an opaque failure carries NO status, which is what makes the
        // real handler retry it. A fake that attached one would be silently unretryable.
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        upstream.Attempts.Should().Be(2);
    }

    [Fact]
    public async Task The_fake_upstreams_timeout_has_the_shape_a_real_client_timeout_has()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondTimeout();

        using var http = new HttpClient(upstream) { BaseAddress = new Uri(ApiEngineFixture.BaseAddress) };
        var call = async () => await http.GetAsync("/notes/1", Ct);

        // A cancelled task wrapping a TimeoutException, as a real HttpClient timeout produces. A plain
        // cancellation would let the caller's "timed out" branch pass here and misreport in production.
        var thrown = await call.Should().ThrowAsync<TaskCanceledException>();
        thrown.Which.InnerException.Should().BeOfType<TimeoutException>();
    }

    [Fact]
    public async Task The_fake_upstreams_bare_status_and_text_bodies_classify_as_transport_failures()
    {
        var caller = new ApiCaller(ApiEngineFixture.Config(), ApiEngineFixture.TypeUris);
        var upstream = new FakeUpstream("notes");
        upstream.RespondStatus(HttpStatusCode.ServiceUnavailable);
        upstream.RespondText(HttpStatusCode.BadGateway, "<html>502</html>");

        var silent = await Classify(caller, upstream);
        var garbage = await Classify(caller, upstream);

        silent.Status.Should().Be(504);
        garbage.Status.Should().Be(504);
    }

    [Fact]
    public async Task Every_fixture_body_classifies_the_way_its_name_claims()
    {
        var caller = new ApiCaller(ApiEngineFixture.Config(), ApiEngineFixture.TypeUris);
        var upstream = new FakeUpstream("notes");
        upstream.RespondProblem(
            HttpStatusCode.NotFound,
            UpstreamResponses.Problem("https://errors.other.invalid/p", "Missing", 404, "gone"));
        upstream.RespondJson(
            HttpStatusCode.NotFound,
            UpstreamResponses.NestedProblem("error", "https://errors.other.invalid/p", "Missing", 404, "wrapped"));
        upstream.RespondJson(HttpStatusCode.BadRequest, UpstreamResponses.NonProblemJson("legacy", 4001));

        var direct = await Classify(caller, upstream);
        var nested = await Classify(caller, upstream);
        var legacy = await Classify(caller, upstream);

        // Validated against the real classifier rather than by reading the JSON: a fixture whose shape
        // has drifted still looks right to a reader and is silently no longer the case it names.
        direct.Type.Should().Be("https://errors.other.invalid/p");
        nested.Type.Should().Be("https://errors.other.invalid/p");
        nested.Detail.Should().Be("wrapped");
        legacy.Status.Should().Be(502);
    }

    [Fact]
    public void The_problem_fixture_carries_optional_recoverability_and_data()
    {
        var body = UpstreamResponses.Problem(
            "https://errors.other.invalid/p",
            "Missing",
            404,
            "gone",
            recoverable: true,
            data: new JsonObject { ["id"] = "n-1" });

        var parsed = JsonNode.Parse(body)!.AsObject();
        parsed["recoverable"]!.GetValue<bool>().Should().BeTrue();
        parsed["data"]!["id"]!.GetValue<string>().Should().Be("n-1");
    }

    [Fact]
    public void The_problem_fixture_omits_data_when_none_is_supplied()
    {
        var parsed = JsonNode.Parse(UpstreamResponses.Problem("t", "T", 404, "d"))!.AsObject();

        parsed.ContainsKey("data").Should().BeFalse("an absent extension must be absent, not null");
    }

    [Fact]
    public void The_nested_fixture_refuses_a_blank_wrapper_member()
    {
        var build = () => UpstreamResponses.NestedProblem("  ", "t", "T", 404, "d");
        build.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void The_payload_fixture_serializes_through_the_platform_contract()
    {
        var body = UpstreamResponses.Payload(new { NoteId = "n-1", Count = 2 });

        // camelCase, because that is what the wire contract says and what a consumer's generated client
        // will be expecting.
        body.Should().Be("{\"noteId\":\"n-1\",\"count\":2}");
    }

    [Fact]
    public void The_fake_client_tree_resolves_what_was_registered_and_records_the_lookups()
    {
        var tree = new FakeClientTree();
        var client = new object();
        tree.Register(ApiEngineFixture.Notes, client);

        tree.Get<object>(ApiEngineFixture.Notes).Should().BeSameAs(client);
        tree.Resolved.Should().Equal(ApiEngineFixture.Notes);
    }

    [Fact]
    public void The_fake_client_tree_refuses_an_unregistered_address_like_the_real_one()
    {
        var tree = new FakeClientTree();

        var resolve = () => tree.Get<object>(ApiEngineFixture.Notes);

        resolve.Should().Throw<InvalidOperationException>().WithMessage("*No client is registered*");
    }

    [Fact]
    public void The_fake_client_tree_distinguishes_a_wrong_type_from_a_missing_registration()
    {
        var tree = new FakeClientTree();
        tree.Register(ApiEngineFixture.Notes, "a string client");

        var resolve = () => tree.Get<HttpClient>(ApiEngineFixture.Notes);

        // Reporting a type mismatch as "not registered" would send the reader looking for a Register
        // call that is actually there.
        resolve.Should().Throw<InvalidOperationException>().WithMessage("*registered as String*");
    }

    [Fact]
    public void The_fake_client_tree_rejects_null_arguments()
    {
        var tree = new FakeClientTree();

        var nullAddress = () => tree.Register<object>(null!, new object());
        var nullClient = () => tree.Register<object>(ApiEngineFixture.Notes, null!);
        var nullGet = () => tree.Get<object>(null!);

        nullAddress.Should().Throw<ArgumentNullException>();
        nullClient.Should().Throw<ArgumentNullException>();
        nullGet.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task The_token_helper_mints_one_token_per_resource_with_no_cross_bleed()
    {
        var cache = FakeTokens.Cache("https://a.test.invalid", "https://b.test.invalid");

        var first = await cache.GetAsync("https://a.test.invalid", cancellationToken: Ct);
        var second = await cache.GetAsync("https://b.test.invalid", cancellationToken: Ct);

        // The token embeds its resource on purpose: a constant token would make a cross-backend leak
        // invisible in exactly the test written to catch one.
        first.Get().Token.Should().Be(FakeTokens.TokenFor("https://a.test.invalid"));
        second.Get().Token.Should().NotBe(first.Get().Token);
    }

    [Fact]
    public async Task The_token_helper_composes_over_auth_engines_own_credential_fake()
    {
        var credentials = new FakeCredentialClient();
        var clock = new FakeAuthClock();
        credentials.ScriptToken("https://a.test.invalid", "scripted", clock.UtcNow.AddMinutes(30));

        var cache = FakeTokens.Cache(credentials, clock);
        var token = await cache.GetAsync("https://a.test.invalid", cancellationToken: Ct);

        // Consumed rather than reimplemented: a second fake of the same port would drift from the
        // contract it imitates, which is the failure a shared fake exists to prevent.
        token.Get().Token.Should().Be("scripted");
        credentials.AcquireCount.Should().Be(1);
    }

    [Fact]
    public void The_fake_upstream_rejects_a_blank_name_and_a_null_responder()
    {
        var blankName = () => new FakeUpstream("  ");
        var nullResponder = () => new FakeUpstream("notes").Respond(null!);

        blankName.Should().Throw<ArgumentException>();
        nullResponder.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task The_fake_upstream_rejects_a_null_request()
    {
        var upstream = new FakeUpstream("notes");
        using var invoker = new HttpMessageInvoker(upstream);

        var send = () => invoker.SendAsync(null!, Ct);
        await send.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public void The_recorded_request_is_a_value_a_test_can_compare()
    {
        var uri = new Uri("https://notes.test.invalid/notes/1");
        var first = new RecordedRequest(HttpMethod.Get, uri, "Bearer t", "body");
        var second = new RecordedRequest(HttpMethod.Get, uri, "Bearer t", "body");

        first.Should().Be(second);
    }

    private static async Task<AtomiCloud.Diene.Problems.Problem> Classify(IApiCaller caller, FakeUpstream upstream)
    {
        using var http = new HttpClient(new FailureCaptureHandler { InnerHandler = upstream })
        {
            BaseAddress = new Uri(ApiEngineFixture.BaseAddress),
        };

        var outcome = await caller.Call(
            ApiEngineFixture.Notes,
            async token =>
            {
                using var response = await http.GetAsync("/notes/1", token);
                response.EnsureSuccessStatusCode();
                return 1;
            },
            Ct);

        return outcome.GetFailure();
    }
}
