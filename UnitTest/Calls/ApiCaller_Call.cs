using AtomiCloud.Diene.ApiEngine.Calls;
using AtomiCloud.Diene.ApiEngine.TestHelper.Assertions;
using AtomiCloud.Diene.ApiEngine.TestHelper.Builders;
using AtomiCloud.Diene.ApiEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ApiEngine.Transport;
using AtomiCloud.Diene.ApiEngine.Upstreams;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Calls;

/// <summary>
/// The wrapper every call site uses: what it returns, and — more importantly — what it never throws.
/// </summary>
public class ApiCaller_Call
{
    private static readonly IApiCaller Caller = new ApiCaller(ApiEngineFixture.Config(), ApiEngineFixture.TypeUris);

    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task A_successful_call_returns_its_value()
    {
        var outcome = await Caller.Call(ApiEngineFixture.Notes, _ => Task.FromResult(41 + 1), Ct);

        outcome.Should().BeOk(42);
    }

    [Fact]
    public async Task A_successful_value_free_call_returns_unit()
    {
        var ran = false;

        var outcome = await Caller.Call(
            ApiEngineFixture.Notes,
            _ =>
            {
                ran = true;
                return Task.CompletedTask;
            },
            Ct);

        outcome.Should().BeOk(new Unit());
        ran.Should().BeTrue("the wrapped work must actually run, not merely be accepted");
    }

    [Fact]
    public async Task A_carried_domain_problem_surfaces_as_that_problem_rather_than_as_transport()
    {
        var outcome = await Caller.Call<int>(
            ApiEngineFixture.Notes,
            _ => throw new Unauthenticated("The token was rejected.").ToException(),
            Ct);

        // The distinction is the point. An IdP outage flattened into "the upstream was unreachable"
        // sends a reader to the wrong service, and this is the seam where that flattening would happen.
        outcome.ShouldBeProblem().ShouldHaveStatus(401);
        outcome.ShouldBeProblem().Should().HaveType(ApiEngineFixture.TypeUri("v1", "unauthenticated"));
        outcome.ShouldBeProblem().Detail.Should().Be("The token was rejected.");
    }

    [Fact]
    public async Task A_carried_authorization_problem_keeps_its_own_status()
    {
        var outcome = await Caller.Call<int>(
            ApiEngineFixture.Notes,
            _ => throw new Unauthorized("Missing scope.", ["notes:read"], ["notes:write"]).ToException(),
            Ct);

        outcome.ShouldBeProblem().ShouldHaveStatus(403);
    }

    [Fact]
    public async Task An_unreachable_upstream_becomes_a_transport_failure_and_throws_nothing()
    {
        var outcome = await Caller.Call<int>(
            ApiEngineFixture.Notes,
            _ => throw new HttpRequestException("connection refused"),
            Ct);

        var payload = outcome.ShouldBeTransportFailure();
        payload.Upstream.Should().Be(ApiEngineFixture.Notes.ToString());
        payload.UpstreamStatus.Should().BeNull();
        outcome.ShouldBeProblem().Detail.Should().Contain("could not be reached");
    }

    [Fact]
    public async Task A_status_carrying_transport_exception_is_reported_as_an_answer_not_a_reachability_failure()
    {
        var outcome = await Caller.Call<int>(
            ApiEngineFixture.Notes,
            _ => throw new HttpRequestException("bad request", null, System.Net.HttpStatusCode.BadRequest),
            Ct);

        // "Could not be reached" would be a true-sounding sentence about the wrong thing: a status
        // means the exchange completed. It is what sends someone to check network policy for a
        // contract mismatch.
        outcome.ShouldBeProblem().Detail.Should().Contain("answered with status 400");
    }

    [Fact]
    public async Task A_timeout_is_reported_as_a_timeout()
    {
        var outcome = await Caller.Call<int>(
            ApiEngineFixture.Notes,
            _ => throw new TaskCanceledException("timed out", new TimeoutException()),
            Ct);

        outcome.ShouldBeProblem().Detail.Should().Contain("timed out");
    }

    [Fact]
    public async Task A_cancellation_is_reported_as_a_cancellation()
    {
        using var source = new CancellationTokenSource();
        await source.CancelAsync();

        var outcome = await Caller.Call<int>(
            ApiEngineFixture.Notes,
            token => Task.FromCanceled<int>(token),
            source.Token);

        // A cancelled call is still a Result, not an exception: a caller that cancels its own work
        // should not also have to catch for it.
        outcome.ShouldBeProblem().Detail.Should().Contain("cancelled");
    }

    [Fact]
    public async Task An_unexpected_exception_from_a_generated_client_is_still_absorbed()
    {
        var outcome = await Caller.Call<int>(
            ApiEngineFixture.Notes,
            _ => throw new InvalidOperationException("the generated client had a bad day"),
            Ct);

        // Named in the detail rather than swallowed: an engine that absorbs a defect without saying
        // what it absorbed converts a bug into a mystery.
        outcome.ShouldBeProblem().Detail.Should().Contain("InvalidOperationException");
    }

    [Fact]
    public async Task The_rescue_flag_is_read_from_the_upstreams_own_configuration()
    {
        var armed = new ApiCaller(
            ApiEngineFixture.Config(rescueRoutingEnabled: true),
            ApiEngineFixture.TypeUris);

        var outcome = await armed.Call<int>(
            ApiEngineFixture.Notes,
            _ => throw new HttpRequestException("connection refused"),
            Ct);

        outcome.ShouldBeTransportFailure().Rescuable.Should().BeTrue();
    }

    [Fact]
    public async Task An_unconfigured_upstream_reports_no_rescue_rather_than_failing_to_classify()
    {
        var outcome = await Caller.Call<int>(
            ApiEngineFixture.Archive,
            _ => throw new HttpRequestException("connection refused"),
            Ct);

        // Archive is deliberately absent from this caller's configuration: classification must still
        // produce a problem, because a caller holding an address the config does not know still needs
        // an answer rather than a second exception.
        outcome.ShouldBeTransportFailure().Rescuable.Should().BeFalse();
    }

    [Fact]
    public async Task The_classifier_sees_the_body_the_pipeline_captured()
    {
        var upstream = new FakeUpstream("notes");
        upstream.RespondJson(
            System.Net.HttpStatusCode.BadRequest,
            UpstreamResponses.NonProblemJson("legacy contract", 4001));

        using var handler = Pipeline(upstream);
        using var http = new HttpClient(handler) { BaseAddress = new Uri(ApiEngineFixture.BaseAddress) };

        var outcome = await Caller.Call(
            ApiEngineFixture.Notes,
            async token =>
            {
                using var response = await http.GetAsync("/notes/1", token);
                response.EnsureSuccessStatusCode();
                return 1;
            },
            Ct);

        // This is the whole reason the capture exists: the generated client turned the response into
        // an exception, and the body still reached the classifier.
        outcome.ShouldBeUpstreamRejected().Body.Should().Contain("legacy contract");
    }

    [Fact]
    public async Task Rejects_null_arguments()
    {
        var nullAddress = async () => await Caller.Call(null!, _ => Task.FromResult(1), Ct);
        var nullCall = async () => await Caller.Call<int>(ApiEngineFixture.Notes, null!, Ct);
        var nullVoidCall = async () => await Caller.Call(ApiEngineFixture.Notes, (Func<CancellationToken, Task>)null!, Ct);

        await nullAddress.Should().ThrowAsync<ArgumentNullException>();
        await nullCall.Should().ThrowAsync<ArgumentNullException>();
        await nullVoidCall.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public void Rejects_construction_without_configuration_or_a_type_uri_builder()
    {
        var noConfig = () => new ApiCaller(null!, ApiEngineFixture.TypeUris);
        var noTypeUris = () => new ApiCaller(ApiEngineFixture.Config(), null!);

        noConfig.Should().Throw<ArgumentNullException>();
        noTypeUris.Should().Throw<ArgumentNullException>();
    }

    private static DelegatingHandler Pipeline(FakeUpstream upstream) =>
        new RetryOnceHandler { InnerHandler = new FailureCaptureHandler { InnerHandler = upstream } };
}
