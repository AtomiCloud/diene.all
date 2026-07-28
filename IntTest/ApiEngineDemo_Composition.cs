using System.Text.Json;
using AtomiCloud.Diene.ApiEngine.Calls;
using AtomiCloud.Diene.ApiEngine.Client;
using AtomiCloud.Diene.ApiEngine.TestHelper.Assertions;
using AtomiCloud.Diene.ApiEngine.Transport;
using AtomiCloud.Diene.ApiEngine.Upstreams;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using AtomiCloud.DotnetBase.App;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.IntTest;

/// <summary>
/// Drives the whole engine against a REAL HTTP upstream over a loopback socket.
/// </summary>
/// <remarks>
/// The unit suite proves the classifier against bodies the suite itself writes. This tier proves
/// the same conclusions against bodies produced by an independent server, over real transport, with
/// the real handler pipeline in place — the only venue where "no exception escapes a wrapped call"
/// is a claim about HTTP rather than about a message-handler double.
/// </remarks>
public sealed class ApiEngineDemo_Composition : IAsyncLifetime
{
    private DemoUpstream _upstream = null!;
    private ServiceProvider _services = null!;

    /// <summary>The ambient test cancellation token, so a hung upstream cancels with the run.</summary>
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    /// <inheritdoc />
    public async ValueTask InitializeAsync()
    {
        _upstream = await DemoUpstream.StartAsync();
        _services = ApiEngineDemo.Compose(ApiEngineDemo.BuildConfig(_upstream.BaseAddress).Get());
    }

    /// <inheritdoc />
    public async ValueTask DisposeAsync()
    {
        await _services.DisposeAsync();
        await _upstream.DisposeAsync();
    }

    [Fact]
    public void BuildConfig_resolves_the_iso_duration_timeout_and_every_upstream()
    {
        var config = ApiEngineDemo.BuildConfig(_upstream.BaseAddress).Get();

        config.Upstreams.Should().HaveCount(3);
        config.Find(ApiEngineDemo.Notes).Get().Timeout.Should().Be(TimeSpan.FromSeconds(5));
        config.Find(ApiEngineDemo.Notes).Get().AuthResource.Should().Be(ApiEngineDemo.NotesResource);
        config.Find(ApiEngineDemo.Unreachable).Get().AuthResource.Should().BeNull();
    }

    [Fact]
    public async Task A_successful_call_returns_the_typed_payload()
    {
        var described = await ApiEngineDemo.Describe(_services, ApiEngineDemo.Notes, DemoUpstream.OkPath, Ct);
        described.Should().Be($"{DemoUpstream.OkPath} -> ok: note-1 'A real payload'");
    }

    [Fact]
    public async Task A_value_free_call_succeeds_as_unit()
    {
        var described = await ApiEngineDemo.DescribePing(_services, ApiEngineDemo.Notes, DemoUpstream.OkPath, Ct);
        described.Should().Be($"{DemoUpstream.OkPath} -> ok (no payload)");
    }

    [Fact]
    public async Task An_upstream_problem_is_passed_through_unaltered()
    {
        var outcome = await Call(ApiEngineDemo.Notes, DemoUpstream.ProblemPath);

        // Asserted by the upstream's OWN type URI: a re-enveloped failure would still be a failure
        // here, and only the contract identity distinguishes the two.
        outcome.ShouldBePassedThrough(DemoUpstream.ProblemType).ShouldHaveStatus(404);
    }

    [Fact]
    public async Task A_problem_nested_inside_a_wrapper_is_still_found()
    {
        var outcome = await Call(ApiEngineDemo.Notes, DemoUpstream.NestedProblemPath);

        var problem = outcome.ShouldBePassedThrough(DemoUpstream.ProblemType);
        problem.ShouldHaveStatus(404);
        problem.Detail.Should().Be("Wrapped by a gateway.");
    }

    [Fact]
    public async Task A_non_problem_json_failure_becomes_an_upstream_rejection()
    {
        var outcome = await Call(ApiEngineDemo.Notes, DemoUpstream.LegacyPath);

        outcome.ShouldBeProblem().ShouldHaveStatus(ApiEngineProblems.UpstreamRejectedStatus);
        var payload = outcome.ShouldBeUpstreamRejected();
        payload.Upstream.Should().Be(ApiEngineDemo.Notes.ToString());
        payload.UpstreamStatus.Should().Be(400);

        // Verbatim rather than summarised: the bytes that did not match are what makes a contract
        // mismatch diagnosable from the problem alone.
        payload.Body.Should().Contain("another error contract");
    }

    [Fact]
    public async Task A_non_json_failure_body_becomes_a_transport_failure_with_a_snippet()
    {
        var outcome = await Call(ApiEngineDemo.Notes, DemoUpstream.GarbagePath);

        outcome.ShouldBeProblem().ShouldHaveStatus(ApiEngineProblems.UpstreamTransportFailureStatus);
        var payload = outcome.ShouldBeTransportFailure();
        payload.UpstreamStatus.Should().Be(502);
        payload.ContentType.Should().Be("text/html");
        payload.BodySnippet.Should().Contain("502 Bad Gateway");
    }

    [Fact]
    public async Task A_status_only_failure_becomes_a_transport_failure_with_no_snippet()
    {
        var outcome = await Call(ApiEngineDemo.Notes, DemoUpstream.SilentPath);

        var payload = outcome.ShouldBeTransportFailure();
        payload.UpstreamStatus.Should().Be(503);
        payload.BodySnippet.Should().BeEmpty();
    }

    [Fact]
    public async Task Each_backend_carries_its_own_token_and_neither_sees_the_other()
    {
        await ApiEngineDemo.Describe(_services, ApiEngineDemo.Notes, DemoUpstream.OkPath, Ct);
        await ApiEngineDemo.Describe(_services, ApiEngineDemo.Archive, DemoUpstream.OkPath, Ct);

        // Both upstreams share one host, so a leak shows up as the wrong resource in a header the
        // server itself recorded, rather than as an absence a passing test could hide.
        _upstream.Authorizations.Should().Contain($"Bearer demo-token-for-{ApiEngineDemo.NotesResource}");
        _upstream.Authorizations.Should().Contain($"Bearer demo-token-for-{ApiEngineDemo.ArchiveResource}");
        _upstream.Authorizations.Distinct().Should().HaveCount(2);
    }

    [Fact]
    public async Task An_unauthenticated_upstream_sends_no_authorization_header()
    {
        await ApiEngineDemo.Describe(_services, ApiEngineDemo.Notes, DemoUpstream.OkPath, Ct);
        var before = _upstream.Authorizations.Count;

        await ApiEngineDemo.DescribeUnreachable(_services, Ct);

        // The unreachable upstream has no auth binding, so no handler was added for it. Counted
        // rather than inspected: an assertion that no header "contains" its resource would also
        // pass if the request had never been made.
        _upstream.Authorizations.Should().HaveCount(before);
    }

    [Fact]
    public async Task An_opaque_connect_failure_is_retried_exactly_once_and_then_surfaces()
    {
        var described = await ApiEngineDemo.DescribeUnreachable(_services, Ct);

        // Two attempts, as a number: "it retried" is unfalsifiable, and a profile that retried twice
        // or not at all would satisfy any looser assertion.
        //
        // The ceiling is interpolated from the same constant the demo formats with, rather than
        // spelled out. An earlier version of this line hard-coded the whole phrase and went stale the
        // moment the demo's wording changed — the behaviour was still correct and the test still went
        // red, which is what an assertion coupled to prose rather than to a value buys you.
        described.Should().Contain($"after 2 of at most {RetryOnceHandler.MaxAttempts} attempt(s)");
        described.Should().Contain("rescuable True");
        described.Should().Contain($"problem {ApiEngineProblems.UpstreamTransportFailureStatus}");
    }

    [Fact]
    public async Task The_transport_failure_payload_round_trips_through_the_wire()
    {
        var outcome = await Call(ApiEngineDemo.Unreachable, DemoUpstream.OkPath);
        var problem = outcome.ShouldBeProblem();

        // Decoded from the serialized envelope rather than the in-memory instance: a payload that
        // only reads back in process is useless to the caller receiving it over HTTP.
        var decoded = problem.Data!.Deserialize<UpstreamTransportFailure>(AtomiJson.DefaultOptions);
        decoded!.Attempts.Should().Be(2);
        decoded.Upstream.Should().Be(ApiEngineDemo.Unreachable.ToString());
        decoded.UpstreamStatus.Should().BeNull("no status ever arrived");
    }

    [Fact]
    public async Task No_exception_escapes_any_branch_of_the_matrix()
    {
        string[] paths =
        [
            DemoUpstream.OkPath,
            DemoUpstream.ProblemPath,
            DemoUpstream.NestedProblemPath,
            DemoUpstream.LegacyPath,
            DemoUpstream.GarbagePath,
            DemoUpstream.SilentPath,
        ];

        foreach (var path in paths)
        {
            var call = async () => await Call(ApiEngineDemo.Notes, path);
            await call.Should().NotThrowAsync($"the wrapper must absorb every outcome of {path}");
        }
    }

    [Fact]
    public void An_unregistered_upstream_is_refused_rather_than_resolving_to_nothing()
    {
        var tree = _services.GetRequiredService<IClientTree>();
        var absent = ServiceAddress.Create("lithium", "notes", "absent").Get();

        var resolve = () => tree.Get<NotesClient>(absent);
        resolve.Should().Throw<InvalidOperationException>().WithMessage("*absent*");
    }

    [Fact]
    public async Task The_demo_runs_end_to_end_and_reports_success()
    {
        var exit = await Program.Main([]);
        exit.Should().Be(0);
    }

    private async Task<Result<NoteView, Problem>> Call(ServiceAddress address, string path)
    {
        var tree = _services.GetRequiredService<IClientTree>();
        var caller = _services.GetRequiredService<IApiCaller>();
        var client = tree.Get<NotesClient>(address);
        return await caller.Call(address, token => client.GetAsync(path, token), Ct);
    }
}
