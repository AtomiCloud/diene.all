using System.Net;
using AtomiCloud.Diene.ApiEngine.Calls;
using AtomiCloud.Diene.ApiEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ApiEngine.Transport;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Transport;

/// <summary>
/// The handler that carries a failed exchange out of the pipeline for the classifier to read.
/// </summary>
public class FailureCaptureHandler_SendAsync
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Records_the_status_media_type_and_body_of_a_failure()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondJson(HttpStatusCode.BadRequest, "{\"code\":1}");

        using var scope = new ApiCallScope();
        using var http = Client(upstream);
        using var response = await http.GetAsync("/notes/1", Ct);

        scope.Capture.Failure!.Status.Should().Be(400);
        scope.Capture.Failure.ContentType.Should().Be("application/json");
        scope.Capture.Failure.Body.Should().Be("{\"code\":1}");
    }

    [Fact]
    public async Task Leaves_the_body_readable_by_the_caller_after_recording_it()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondJson(HttpStatusCode.BadRequest, "{\"code\":1}");

        using var scope = new ApiCallScope();
        using var http = Client(upstream);
        using var response = await http.GetAsync("/notes/1", Ct);
        var body = await response.Content.ReadAsStringAsync(Ct);

        // The content is BUFFERED rather than replaced, so the generated client still reads exactly
        // the bytes it would have read. A substituted HttpContent would silently drop the original
        // content headers, and the failure would show up as a deserialization error much later.
        body.Should().Be("{\"code\":1}");
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/json");
    }

    [Fact]
    public async Task Records_nothing_for_a_success()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondOk("{\"id\":\"n-1\"}");

        using var scope = new ApiCallScope();
        using var http = Client(upstream);
        using var response = await http.GetAsync("/notes/1", Ct);

        // A success needs no capture: the caller already has its typed value, and recording one would
        // leave a stale failure for a later call in the same scope to be classified against.
        scope.Capture.Failure.Should().BeNull();
        scope.Capture.Attempts.Should().Be(1);
    }

    [Fact]
    public async Task Counts_every_attempt_including_a_retried_one()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondNetworkFailure();
        upstream.RespondJson(HttpStatusCode.BadGateway, "not json");

        using var scope = new ApiCallScope();
        using var http = new HttpClient(
            new RetryOnceHandler { InnerHandler = new FailureCaptureHandler { InnerHandler = upstream } })
        {
            BaseAddress = new Uri(ApiEngineFixture.BaseAddress),
        };
        using var response = await http.GetAsync("/notes/1", Ct);

        // Counted innermost, so the number is attempts against the wire rather than calls into the
        // pipeline — which is what makes "exactly one retry" checkable from a problem payload.
        scope.Capture.Attempts.Should().Be(2);
        scope.Capture.Failure!.Status.Should().Be(502);
    }

    [Fact]
    public async Task Does_nothing_outside_a_wrapped_call()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondJson(HttpStatusCode.BadRequest, "{\"code\":1}");

        using var http = Client(upstream);
        using var response = await http.GetAsync("/notes/1", Ct);

        // A consumer's own HttpClient must not be affected by an engine handler it happens to share a
        // process with.
        ApiCallScope.Active.Should().BeNull();
        (await response.Content.ReadAsStringAsync(Ct)).Should().Be("{\"code\":1}");
    }

    private static HttpClient Client(FakeUpstream upstream) =>
        new(new FailureCaptureHandler { InnerHandler = upstream })
        {
            BaseAddress = new Uri(ApiEngineFixture.BaseAddress),
        };
}
