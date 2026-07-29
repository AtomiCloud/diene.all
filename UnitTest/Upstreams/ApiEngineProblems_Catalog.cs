using AtomiCloud.Diene.ApiEngine.Upstreams;
using AtomiCloud.Diene.Problems;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Upstreams;

/// <summary>
/// The two problems this engine originates, and their registration in a consumer's catalog.
/// </summary>
public class ApiEngineProblems_Catalog
{
    [Fact]
    public void Registers_both_problems_with_the_statuses_the_classifier_stamps()
    {
        var catalog = new ProblemCatalogBuilder().AddApiEngineProblems().Build();

        // The same constants the classifier reads. Asserting the catalog row against a literal here
        // would let the two drift apart while both tests kept passing.
        catalog.StatusOf(new UpstreamRejected()).Should().Be(ApiEngineProblems.UpstreamRejectedStatus);
        catalog.StatusOf(new UpstreamTransportFailure())
            .Should().Be(ApiEngineProblems.UpstreamTransportFailureStatus);
    }

    [Fact]
    public void Registers_recoverability_the_way_the_classifier_reports_it()
    {
        var catalog = new ProblemCatalogBuilder().AddApiEngineProblems().Build();

        catalog.Find("v1", "upstream_rejected").Get().Recoverable
            .Should().Be(ApiEngineProblems.UpstreamRejectedRecoverable);
        catalog.Find("v1", "upstream_transport_failure").Get().Recoverable
            .Should().Be(ApiEngineProblems.UpstreamTransportFailureRecoverable);
    }

    [Fact]
    public void Registers_exactly_the_two_problems_this_engine_owns()
    {
        var catalog = new ProblemCatalogBuilder().AddApiEngineProblems().Build();

        catalog.All.Select(descriptor => descriptor.Id)
            .Should().BeEquivalentTo("upstream_rejected", "upstream_transport_failure");
    }

    [Fact]
    public void Composes_with_a_consumers_own_registrations()
    {
        var catalog = new ProblemCatalogBuilder().AddBaseline().AddApiEngineProblems().Build();

        catalog.Find("v1", "upstream_rejected").IsSome().Should().BeTrue();
        catalog.Find("v1", "entity_not_found").IsSome().Should().BeTrue();
    }

    [Fact]
    public void Rejects_a_null_catalog()
    {
        var register = () => ApiEngineProblems.AddApiEngineProblems(null!);
        register.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void The_rejection_problem_carries_the_upstreams_answer()
    {
        var problem = new UpstreamRejected("detail", "lithium.notes.note", 400, "application/json", "{}");

        problem.Id.Should().Be("upstream_rejected");
        problem.Title.Should().Be("Upstream Rejected");
        problem.Version.Should().Be("v1");
        problem.Detail.Should().Be("detail");
        problem.Upstream.Should().Be("lithium.notes.note");
        problem.UpstreamStatus.Should().Be(400);
        problem.ContentType.Should().Be("application/json");
        problem.Body.Should().Be("{}");
    }

    [Fact]
    public void The_rejection_problem_tolerates_an_absent_media_type()
    {
        var problem = new UpstreamRejected("detail", "lithium.notes.note", 400, null, "{}");

        // Empty rather than null: the payload is serialized into a problem envelope, and a null there
        // would read as "the field is missing" instead of "the upstream declared no media type".
        problem.ContentType.Should().BeEmpty();
    }

    [Fact]
    public void The_transport_problem_carries_whatever_detail_existed()
    {
        var problem = new UpstreamTransportFailure("detail", "lithium.notes.note", null, null, null, 2, true);

        problem.Id.Should().Be("upstream_transport_failure");
        problem.Title.Should().Be("Upstream Transport Failure");
        problem.Version.Should().Be("v1");
        problem.UpstreamStatus.Should().BeNull("no status ever arrived");
        problem.ContentType.Should().BeEmpty();
        problem.BodySnippet.Should().BeEmpty();
        problem.Attempts.Should().Be(2);
        problem.Rescuable.Should().BeTrue();
    }

    [Fact]
    public void The_transport_problem_bounds_the_snippet_it_keeps()
    {
        var body = new string('y', UpstreamTransportFailure.BodySnippetLength + 1);

        var problem = new UpstreamTransportFailure("detail", "u", 502, "text/html", body, 1, false);

        problem.BodySnippet.Should().HaveLength(UpstreamTransportFailure.BodySnippetLength);
    }

    [Fact]
    public void The_transport_problem_keeps_a_body_that_already_fits()
    {
        var problem = new UpstreamTransportFailure("detail", "u", 502, "text/html", "short", 1, false);

        problem.BodySnippet.Should().Be("short");
    }

    [Fact]
    public void Both_problems_reject_the_arguments_they_cannot_do_without()
    {
        var rejectedNoDetail = () => new UpstreamRejected(null!, "u", 400, null, "{}");
        var rejectedNoUpstream = () => new UpstreamRejected("d", null!, 400, null, "{}");
        var rejectedNoBody = () => new UpstreamRejected("d", "u", 400, null, null!);
        var transportNoDetail = () => new UpstreamTransportFailure(null!, "u", null, null, null, 1, false);
        var transportNoUpstream = () => new UpstreamTransportFailure("d", null!, null, null, null, 1, false);

        rejectedNoDetail.Should().Throw<ArgumentNullException>();
        rejectedNoUpstream.Should().Throw<ArgumentNullException>();
        rejectedNoBody.Should().Throw<ArgumentNullException>();
        transportNoDetail.Should().Throw<ArgumentNullException>();
        transportNoUpstream.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Both_problems_construct_empty_for_catalog_registration_and_schema_export()
    {
        // The parameterless form is what ProblemCatalogBuilder.Add<T> instantiates, so it must produce
        // a usable identity rather than a half-initialised object.
        new UpstreamRejected().Id.Should().Be("upstream_rejected");
        new UpstreamTransportFailure().Id.Should().Be("upstream_transport_failure");
        new UpstreamRejected().Detail.Should().BeEmpty();
        new UpstreamTransportFailure().Detail.Should().BeEmpty();
    }
}
