using System.Net;
using System.Net.Http.Headers;
using AtomiCloud.Diene.ApiEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ApiEngine.Transport;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Transport;

/// <summary>
/// The whole client-side resilience profile: exactly one retry, only on an opaque failure.
/// </summary>
/// <remarks>
/// Every case here asserts an attempt COUNT rather than an outcome. "It retried" is unfalsifiable —
/// a handler that retried three times, or that returned a cached success, satisfies any assertion
/// phrased that way.
/// </remarks>
public class RetryOnceHandler_SendAsync
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Retries_an_opaque_network_failure_exactly_once()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondNetworkFailure();
        upstream.RespondOk("{}");

        using var http = Client(upstream);
        using var response = await http.GetAsync("/notes/1", Ct);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        upstream.Attempts.Should().Be(2);
    }

    [Fact]
    public async Task Surfaces_the_second_failure_rather_than_retrying_again()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondNetworkFailure();
        upstream.RespondNetworkFailure();

        using var http = Client(upstream);
        var call = async () => await http.GetAsync("/notes/1", Ct);

        await call.Should().ThrowAsync<HttpRequestException>();
        upstream.Attempts.Should().Be(RetryOnceHandler.MaxAttempts);
    }

    [Theory]
    [InlineData(HttpStatusCode.InternalServerError)]
    [InlineData(HttpStatusCode.BadGateway)]
    [InlineData(HttpStatusCode.NotFound)]
    public async Task Never_retries_a_received_status(HttpStatusCode status)
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondStatus(status);

        using var http = Client(upstream);
        using var response = await http.GetAsync("/notes/1", Ct);

        // Not even a 5xx. A status means the request arrived and was processed, so retrying risks
        // repeating a non-idempotent effect for no gain.
        response.StatusCode.Should().Be(status);
        upstream.Attempts.Should().Be(1);
    }

    [Fact]
    public async Task Never_retries_a_transport_exception_that_carries_a_status()
    {
        var upstream = new FakeUpstream("notes");
        upstream.Respond(_ => throw new HttpRequestException("gateway said no", null, HttpStatusCode.BadGateway));

        using var http = Client(upstream);
        var call = async () => await http.GetAsync("/notes/1", Ct);

        // A status on the exception means the exchange completed. It is NOT opaque, so it is not the
        // window this profile covers — and retrying it would repeat a processed request.
        await call.Should().ThrowAsync<HttpRequestException>();
        upstream.Attempts.Should().Be(1);
    }

    [Fact]
    public async Task Never_retries_a_timeout()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondTimeout();

        using var http = Client(upstream);
        var call = async () => await http.GetAsync("/notes/1", Ct);

        // The caller asked for an answer within a budget; spending that budget twice serves it worse
        // than telling it the truth once.
        await call.Should().ThrowAsync<TaskCanceledException>();
        upstream.Attempts.Should().Be(1);
    }

    [Fact]
    public async Task Does_not_retry_once_the_caller_has_cancelled()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondNetworkFailure();
        using var source = new CancellationTokenSource();
        await source.CancelAsync();

        using var http = Client(upstream);
        var call = async () => await http.GetAsync("/notes/1", source.Token);

        await call.Should().ThrowAsync<Exception>();
        upstream.Attempts.Should().Be(1, "a cancelled caller does not want a second attempt");
    }

    [Fact]
    public async Task Replays_the_body_and_headers_on_the_retry()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondNetworkFailure();
        upstream.RespondOk("{}");

        using var http = Client(upstream);
        using var request = new HttpRequestMessage(HttpMethod.Post, "/notes")
        {
            Content = new StringContent("{\"title\":\"replayed\"}", System.Text.Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("X-Trace", "abc");

        using var response = await http.SendAsync(request, Ct);

        // The body is buffered before the first attempt, because a request whose content has already
        // been streamed cannot be sent again — and discovering that during the retry would turn a
        // recoverable blip into a confusing second failure.
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        upstream.Requests.Should().HaveCount(2);
        upstream.Requests[1].Body.Should().Be("{\"title\":\"replayed\"}");
        upstream.Requests[1].Method.Should().Be(HttpMethod.Post);
        upstream.Requests[1].Uri!.AbsolutePath.Should().Be("/notes");
    }

    [Fact]
    public async Task Replays_the_authorization_header_so_the_retry_is_not_anonymous()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondNetworkFailure();
        upstream.RespondOk("{}");

        using var http = Client(upstream);
        using var request = new HttpRequestMessage(HttpMethod.Get, "/notes/1");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", "token-1");

        using var response = await http.SendAsync(request, Ct);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        upstream.Requests[1].Authorization.Should().Be("Bearer token-1");
    }

    [Fact]
    public async Task Replays_request_options_so_downstream_handlers_see_the_same_request()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondNetworkFailure();
        upstream.RespondOk("{}");
        var key = new HttpRequestOptionsKey<string>("upstream-key");

        using var http = Client(upstream);
        using var request = new HttpRequestMessage(HttpMethod.Get, "/notes/1");
        request.Options.Set(key, "lithium.notes.note");

        using var response = await http.SendAsync(request, Ct);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        upstream.Requests[1].Uri!.AbsolutePath.Should().Be("/notes/1");
    }

    [Fact]
    public async Task Rejects_a_null_request()
    {
        var handler = new RetryOnceHandler { InnerHandler = new FakeUpstream("notes") };
        var invoker = new HttpMessageInvoker(handler);

        var send = () => invoker.SendAsync(null!, Ct);
        await send.Should().ThrowAsync<ArgumentNullException>();
        invoker.Dispose();
    }

    private static HttpClient Client(FakeUpstream upstream) =>
        new(new RetryOnceHandler { InnerHandler = upstream })
        {
            BaseAddress = new Uri(ApiEngineFixture.BaseAddress),
        };
}
