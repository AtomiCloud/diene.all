using System.Text.Json;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.ApiEngine.TestHelper.Assertions;
using AtomiCloud.Diene.ApiEngine.Upstreams;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Meta;

/// <summary>
/// Assert-the-asserter for the shipped assertions: every one is proven to PASS a known-good case and
/// to FAIL a known-bad one.
/// </summary>
/// <remarks>
/// An assertion helper that only ever runs against passing cases is indistinguishable from one that
/// returns unconditionally — and a shipped assertion that cannot fail silently disarms every consumer
/// suite that trusts it. That is the whole reason this tier exists.
/// </remarks>
public class ApiResultAssertions_Meta
{
    private static readonly Problem Envelope = new()
    {
        Type = "https://errors.test.invalid/docs/lapras/lithium/notes/note/v1/note_missing",
        Title = "Note Missing",
        Status = 404,
        Detail = "Note 'n-1' does not exist.",
    };

    [Fact]
    public void ShouldBeOk_returns_the_value_on_a_success()
    {
        Result.Ok<int, Problem>(7).ShouldBeOk().Should().Be(7);
    }

    [Fact]
    public void ShouldBeOk_fails_on_a_failure_and_names_the_problem()
    {
        var assert = () => Result.Err<int, Problem>(Envelope).ShouldBeOk();

        assert.Should().Throw<ApiAssertionException>()
            .WithMessage("*note_missing*")
            .WithMessage("*404*");
    }

    [Fact]
    public void ShouldBeProblem_returns_the_envelope_on_a_failure()
    {
        Result.Err<int, Problem>(Envelope).ShouldBeProblem().Should().BeSameAs(Envelope);
    }

    [Fact]
    public void ShouldBeProblem_fails_on_a_success_and_names_the_value()
    {
        var assert = () => Result.Ok<int, Problem>(7).ShouldBeProblem();

        assert.Should().Throw<ApiAssertionException>().WithMessage("*7*");
    }

    [Fact]
    public void ShouldBeUpstreamRejected_returns_the_decoded_payload()
    {
        var payload = Failure(new UpstreamRejected("d", "lithium.notes.note", 400, "application/json", "{}"))
            .ShouldBeUpstreamRejected();

        payload.Upstream.Should().Be("lithium.notes.note");
        payload.UpstreamStatus.Should().Be(400);
    }

    [Fact]
    public void ShouldBeUpstreamRejected_fails_when_the_payload_is_a_transport_failure()
    {
        var assert = () =>
            Failure(new UpstreamTransportFailure("d", "u", null, null, null, 1, false)).ShouldBeUpstreamRejected();

        // The two problems are the pair most worth telling apart, so this is the case where a lenient
        // assertion would do the most damage: it would let a suite claim an upstream answered when it
        // never did.
        assert.Should().Throw<ApiAssertionException>().WithMessage("*upstream_rejected*");
    }

    [Fact]
    public void ShouldBeTransportFailure_returns_the_decoded_payload()
    {
        var payload = Failure(new UpstreamTransportFailure("d", "u", 502, "text/html", "boom", 2, true))
            .ShouldBeTransportFailure();

        payload.Attempts.Should().Be(2);
        payload.BodySnippet.Should().Be("boom");
    }

    [Fact]
    public void ShouldBeTransportFailure_fails_on_the_right_identity_with_no_data()
    {
        var identified = new Problem
        {
            Type = "https://errors.test.invalid/docs/lapras/lithium/notes/note/v1/upstream_transport_failure",
        };

        var assert = () => Result.Err<int, Problem>(identified).ShouldBeTransportFailure();

        assert.Should().Throw<ApiAssertionException>().WithMessage("*data was absent*");
    }

    [Fact]
    public void ShouldBeTransportFailure_fails_when_the_data_is_a_different_shape()
    {
        var mismatched = new Problem
        {
            Type = "https://errors.test.invalid/docs/lapras/lithium/notes/note/v1/upstream_transport_failure",
            Data = JsonValue.Create("not an object"),
        };

        var assert = () => Result.Err<int, Problem>(mismatched).ShouldBeTransportFailure();

        // A payload that does not decode must be reported rather than returned as a defaulted
        // instance: a caller asserting on Attempts would otherwise read 0 and believe no retry ran.
        assert.Should().Throw<ApiAssertionException>().WithMessage("*did not decode*");
    }

    [Fact]
    public void ShouldBeTransportFailure_fails_on_an_upstream_problem_that_is_not_this_engines()
    {
        var assert = () => Result.Err<int, Problem>(Envelope).ShouldBeTransportFailure();

        assert.Should().Throw<ApiAssertionException>().WithMessage("*upstream_transport_failure*");
    }

    [Fact]
    public void ShouldBePassedThrough_returns_the_envelope_when_the_type_matches()
    {
        Result.Err<int, Problem>(Envelope).ShouldBePassedThrough(Envelope.Type).Should().BeSameAs(Envelope);
    }

    [Fact]
    public void ShouldBePassedThrough_fails_when_the_engine_re_enveloped_the_failure()
    {
        var assert = () => Failure(new UpstreamRejected("d", "u", 400, null, "{}"))
            .ShouldBePassedThrough(Envelope.Type);

        assert.Should().Throw<ApiAssertionException>().WithMessage("*passed through*");
    }

    [Fact]
    public void ShouldHaveStatus_returns_the_envelope_when_the_status_matches()
    {
        Envelope.ShouldHaveStatus(404).Should().BeSameAs(Envelope);
    }

    [Fact]
    public void ShouldHaveStatus_fails_on_a_different_status_and_prints_both()
    {
        var assert = () => Envelope.ShouldHaveStatus(500);

        assert.Should().Throw<ApiAssertionException>()
            .WithMessage("*500*")
            .WithMessage("*404*");
    }

    [Fact]
    public void ShouldHaveStatus_rejects_a_null_envelope()
    {
        var assert = () => ((Problem)null!).ShouldHaveStatus(404);
        assert.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void The_assertion_exception_offers_every_shape_a_thrower_needs()
    {
        new ApiAssertionException().Message.Should().NotBeNull();
        new ApiAssertionException("message").Message.Should().Be("message");
        new ApiAssertionException("message", new InvalidOperationException("cause"))
            .InnerException.Should().BeOfType<InvalidOperationException>();
    }

    private static Result<int, Problem> Failure(IDomainProblem payload) =>
        Result.Err<int, Problem>(new Problem
        {
            Type = $"https://errors.test.invalid/docs/lapras/lithium/notes/note/{payload.Version}/{payload.Id}",
            Title = payload.Title,
            Status = 502,
            Detail = payload.Detail,
            Data = JsonSerializer.SerializeToNode(payload, payload.GetType(), AtomiJson.DefaultOptions),
        });
}
