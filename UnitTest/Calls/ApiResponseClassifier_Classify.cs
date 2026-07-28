using System.Text.Json.Nodes;
using AtomiCloud.Diene.ApiEngine.Calls;
using AtomiCloud.Diene.ApiEngine.TestHelper.Assertions;
using AtomiCloud.Diene.ApiEngine.TestHelper.Builders;
using AtomiCloud.Diene.ApiEngine.Upstreams;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.Results;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Calls;

/// <summary>
/// The classification matrix, driven directly rather than through a pipeline.
/// </summary>
/// <remarks>
/// Driven at this level because the interesting inputs are bodies HTTP permits but a cooperating
/// server will not send — a truncated stream, a status with no body, JSON nested four deep. Reaching
/// those through a real server means building a server that misbehaves on demand, which moves the
/// specification into the fixture. The integration tier then re-proves the same conclusions over
/// real transport against a server written independently of these cases.
/// </remarks>
public class ApiResponseClassifier_Classify
{
    private const string Upstream = "lithium.notes.note";

    [Fact]
    public void An_upstream_problem_envelope_is_passed_through_verbatim()
    {
        var body = UpstreamResponses.Problem(
            "https://errors.other.invalid/docs/lapras/lithium/notes/note/v1/note_missing",
            "Note Missing",
            404,
            "Note 'n-1' does not exist.",
            recoverable: true,
            data: new JsonObject { ["requestIdentifier"] = "n-1" });

        var problem = Classify(new ApiFailure(404, "application/problem+json", body));

        // Every field survives, including the ones this engine would otherwise have opinions about:
        // re-deriving a status or a recoverability flag here would overwrite the originating
        // service's own contract with a guess.
        problem.Should().HaveType("https://errors.other.invalid/docs/lapras/lithium/notes/note/v1/note_missing");
        problem.Should().HaveStatus(404);
        problem.Should().BeRecoverable(true);
        problem.Detail.Should().Be("Note 'n-1' does not exist.");
        problem.Data!["requestIdentifier"]!.GetValue<string>().Should().Be("n-1");
    }

    [Theory]
    [InlineData("error")]
    [InlineData("problem")]
    [InlineData("anythingAtAll")]
    public void A_problem_nested_under_any_wrapper_member_is_still_found(string wrapper)
    {
        var body = UpstreamResponses.NestedProblem(
            wrapper,
            "https://errors.other.invalid/docs/lapras/lithium/notes/note/v1/note_missing",
            "Note Missing",
            404,
            "Wrapped.");

        var problem = Classify(new ApiFailure(404, "application/json", body));

        // Keyed on the SHAPE rather than on a list of known wrapper names: a member allowlist covers
        // the gateways seen so far and silently fails on the next one.
        problem.Should().HaveStatus(404);
        problem.Detail.Should().Be("Wrapped.");
    }

    [Fact]
    public void A_problem_nested_at_the_depth_limit_is_found()
    {
        var problem = Classify(new ApiFailure(404, "application/json", Nest(ApiResponseClassifier.MaxNestingDepth)));

        problem.Should().HaveStatus(404);
    }

    [Fact]
    public void A_problem_nested_beyond_the_depth_limit_is_not_treated_as_one()
    {
        var problem = Classify(new ApiFailure(
            404,
            "application/json",
            Nest(ApiResponseClassifier.MaxNestingDepth + 1)));

        // Declining to recognise it is the deliberate outcome. An unbounded search would eventually
        // find something problem-shaped inside an arbitrary payload and report an unrelated object as
        // the failure, which is a wrong answer rather than a missing one.
        problem.Should().HaveStatus(ApiEngineProblems.UpstreamRejectedStatus);
    }

    [Theory]
    [InlineData("{\"title\":\"No type\",\"status\":404}")]
    [InlineData("{\"type\":\"about:blank\",\"status\":404}")]
    [InlineData("{\"type\":\"about:blank\",\"title\":\"No status\"}")]
    [InlineData("{\"type\":\"about:blank\",\"title\":\"String status\",\"status\":\"404\"}")]
    [InlineData("{\"type\":123,\"title\":\"Numeric type\",\"status\":404}")]
    public void A_body_missing_any_part_of_the_envelope_contract_is_not_a_problem(string body)
    {
        var problem = Classify(new ApiFailure(400, "application/json", body));

        // All three members are required together: "type", "title" and "status" are each common enough
        // in ordinary payloads that matching on one would classify arbitrary JSON as a problem.
        problem.Should().HaveStatus(ApiEngineProblems.UpstreamRejectedStatus);
    }

    [Fact]
    public void A_non_problem_json_failure_becomes_an_upstream_rejection_carrying_the_body()
    {
        var body = UpstreamResponses.NonProblemJson("no such note", 4001);

        var problem = Classify(new ApiFailure(400, "application/json", body));

        problem.Should().HaveStatus(ApiEngineProblems.UpstreamRejectedStatus);
        problem.Should().BeRecoverable(false, "the upstream answered; asking again gets the same answer");

        var payload = Result.Err<Unit, Problem>(problem).ShouldBeUpstreamRejected();
        payload.Upstream.Should().Be(Upstream);
        payload.UpstreamStatus.Should().Be(400);
        payload.ContentType.Should().Be("application/json");
        payload.Body.Should().Be(body);
    }

    [Fact]
    public void A_rejection_reports_status_zero_when_a_body_arrived_without_one()
    {
        var payload = Result
            .Err<Unit, Problem>(Classify(new ApiFailure(null, "application/json", "{\"code\":1}")))
            .ShouldBeUpstreamRejected();

        // Zero rather than a plausible substitute: a reader can tell the status was absent, which is a
        // different fact from the upstream having answered 500.
        payload.UpstreamStatus.Should().Be(0);
    }

    [Fact]
    public void A_null_member_beside_a_nested_problem_does_not_stop_the_search()
    {
        var body = "{\"meta\":null,\"error\":" + UpstreamResponses.Problem(
            "https://errors.other.invalid/p",
            "Missing",
            404,
            "found past a null") + "}";

        var problem = Classify(new ApiFailure(404, "application/json", body));

        problem.Detail.Should().Be("found past a null");
    }

    [Fact]
    public void A_json_array_body_is_a_rejection_rather_than_a_problem()
    {
        var problem = Classify(new ApiFailure(400, "application/json", "[{\"code\":1}]"));

        problem.Should().HaveStatus(ApiEngineProblems.UpstreamRejectedStatus);
    }

    [Fact]
    public void An_absent_exchange_becomes_a_transport_failure_with_no_status()
    {
        var problem = Classify(null, attempts: 2, rescuable: true);

        problem.Should().HaveStatus(ApiEngineProblems.UpstreamTransportFailureStatus);
        problem.Should().BeRecoverable(true, "an exchange that never happened may succeed later");

        var payload = Result.Err<Unit, Problem>(problem).ShouldBeTransportFailure();
        payload.UpstreamStatus.Should().BeNull();
        payload.BodySnippet.Should().BeEmpty();
        payload.Attempts.Should().Be(2);
        payload.Rescuable.Should().BeTrue();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void A_status_only_response_becomes_a_transport_failure(string? body)
    {
        var problem = Classify(new ApiFailure(503, null, body));

        var payload = Result.Err<Unit, Problem>(problem).ShouldBeTransportFailure();
        payload.UpstreamStatus.Should().Be(503, "a status did arrive, and losing it loses the diagnosis");
        payload.BodySnippet.Should().BeEmpty();
        payload.ContentType.Should().BeEmpty();
    }

    [Theory]
    [InlineData("<html>502</html>")]
    [InlineData("{\"truncated\":")]
    [InlineData("null")]
    public void An_unparseable_body_becomes_a_transport_failure_carrying_a_snippet(string body)
    {
        var problem = Classify(new ApiFailure(502, "text/html", body));

        var payload = Result.Err<Unit, Problem>(problem).ShouldBeTransportFailure();
        payload.UpstreamStatus.Should().Be(502);
        payload.BodySnippet.Should().Be(body);
    }

    [Fact]
    public void A_long_unreadable_body_is_snipped_to_a_bounded_prefix()
    {
        var body = new string('x', UpstreamTransportFailure.BodySnippetLength * 3);

        var payload = Result
            .Err<Unit, Problem>(Classify(new ApiFailure(502, "text/plain", body)))
            .ShouldBeTransportFailure();

        // Bounded rather than complete: an HTML error page or a truncated stream can be arbitrarily
        // long, and a problem payload that grows without limit turns one bad upstream into a logging
        // incident.
        payload.BodySnippet.Should().HaveLength(UpstreamTransportFailure.BodySnippetLength);
        payload.BodySnippet.Should().Be(body[..UpstreamTransportFailure.BodySnippetLength]);
    }

    [Fact]
    public void The_reason_it_was_given_reaches_the_detail()
    {
        var problem = Classify(new ApiFailure(503, null, null), reason: "Upstream 'x' answered with status 503.");

        problem.Detail.Should().StartWith("Upstream 'x' answered with status 503.");
        problem.Detail.Should().Contain("no body to interpret");
    }

    [Fact]
    public void Both_engine_problems_resolve_to_this_services_own_type_uris()
    {
        var rejected = Classify(new ApiFailure(400, "application/json", "{\"code\":1}"));
        var transport = Classify(null);

        rejected.Should().HaveType(ApiEngineFixture.TypeUri("v1", "upstream_rejected"));
        transport.Should().HaveType(ApiEngineFixture.TypeUri("v1", "upstream_transport_failure"));
    }

    private static string Nest(int depth)
    {
        var node = JsonNode.Parse(UpstreamResponses.Problem(
            "https://errors.other.invalid/docs/lapras/lithium/notes/note/v1/note_missing",
            "Note Missing",
            404,
            "Nested."))!;

        for (var level = 0; level < depth; level++) node = new JsonObject { ["wrapper"] = node };
        return node.ToJsonString();
    }

    private static Problem Classify(
        ApiFailure? failure,
        int attempts = 1,
        bool rescuable = false,
        string reason = "The call failed.") =>
        ApiResponseClassifier.Classify(
            Upstream,
            failure,
            attempts,
            rescuable,
            reason,
            ApiEngineFixture.TypeUris);
}
