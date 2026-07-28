using System.Text.Json;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.ServerEngine.Mvc;
using AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Mvc;

public class ProblemEnvelope_FromDomain
{
    [Fact]
    public void It_should_resolve_status_type_and_recoverability_from_the_catalog()
    {
        // Arrange
        var problem = new EntityConflict("Already exists.", typeof(ProblemEnvelope_FromDomain));

        // Act
        var actual = ProblemEnvelope.FromDomain(problem, Catalog(), TypeUris(), "/notes/1", "trace-1");

        // Assert
        actual.Status.Should().Be(409);
        actual.Title.Should().Be("Entity Conflict");
        actual.Detail.Should().Be("Already exists.");
        actual.Instance.Should().Be("/notes/1");
        actual.Recoverable.Should().BeTrue();
        actual.Type.Should().Be(
            "https://errors.test.invalid/docs/lapras/sulfoxide/probe/api/v1/entity_conflict");
    }

    [Fact]
    public void It_should_carry_the_typed_payload_as_the_data_extension()
    {
        // Arrange
        var problem = new EntityNotFound("Absent.", typeof(ProblemEnvelope_FromDomain), "note-9");

        // Act
        var actual = ProblemEnvelope.FromDomain(problem, Catalog(), TypeUris(), "/notes/9", "trace-2");

        // Assert
        actual.Data!["requestIdentifier"]!.GetValue<string>().Should().Be("note-9");
    }

    [Fact]
    public void It_should_record_the_trace_identifier_as_an_extension_member()
    {
        // Arrange
        var problem = new Unauthenticated("No token.");

        // Act
        var actual = ProblemEnvelope.FromDomain(problem, Catalog(), TypeUris(), "/", "trace-3");

        // Assert
        actual.Extensions!["traceId"].GetString().Should().Be("trace-3");
    }

    [Fact]
    public void It_should_fall_back_to_about_blank_for_a_problem_no_catalog_registered()
    {
        // Arrange — a documentation URI for an unregistered problem would 404, so the envelope
        // says it has no contract rather than pointing at one that does not exist.
        var problem = new ProbeUnregisteredProblem();

        // Act
        var actual = ProblemEnvelope.FromDomain(problem, Catalog(), TypeUris(), "/", "trace-4");

        // Assert
        actual.Type.Should().Be(ProblemEnvelope.UnregisteredType);
        actual.Status.Should().Be(500);
        actual.Recoverable.Should().BeFalse();
    }

    [Fact]
    public void It_should_treat_a_version_and_id_collision_under_a_different_type_as_unregistered()
    {
        // Arrange — an id/version pair alone is not identity. A second type claiming a
        // registered pair must not inherit that registration's status or type URI.
        var problem = new ImpostorNotFound();

        // Act
        var actual = ProblemEnvelope.FromDomain(problem, Catalog(), TypeUris(), "/", "trace-5");

        // Assert
        actual.Type.Should().Be(ProblemEnvelope.UnregisteredType);
        actual.Status.Should().Be(500);
    }

    [Fact]
    public void It_should_reject_a_null_problem_catalog_or_builder()
    {
        // Arrange
        var problem = new Unauthenticated("No token.");

        // Act
        var withoutProblem = () => ProblemEnvelope.FromDomain(null!, Catalog(), TypeUris(), "/", "t");
        var withoutCatalog = () => ProblemEnvelope.FromDomain(problem, null!, TypeUris(), "/", "t");
        var withoutTypeUris = () => ProblemEnvelope.FromDomain(problem, Catalog(), null!, "/", "t");

        // Assert
        withoutProblem.Should().Throw<ArgumentNullException>();
        withoutCatalog.Should().Throw<ArgumentNullException>();
        withoutTypeUris.Should().Throw<ArgumentNullException>();
    }

    internal static IProblemCatalog Catalog() => new ProblemCatalogBuilder().AddBaseline().Build();

    internal static IProblemTypeUriBuilder TypeUris() =>
        new ProblemTypeUriBuilder(
            new ErrorPortalConfig(
                "https",
                "errors.test.invalid",
                new ProblemIdentity("lapras", "sulfoxide", "probe", "api")));

    private sealed class ImpostorNotFound : IDomainProblem
    {
        public string Id => "entity_not_found";

        public string Title => "Impostor";

        public string Detail => "Claims a registered id under an unregistered type.";

        public string Version => "v1";
    }
}

public class ProblemEnvelope_FromProtocol
{
    [Fact]
    public void It_should_build_a_transport_refusal_without_consulting_a_catalog()
    {
        // Act
        var actual = ProblemEnvelope.FromProtocol(
            401,
            "Webhook Signature Rejected",
            "The delivery signature was refused.",
            "/internal/webhooks/stripe",
            "trace-6");

        // Assert
        actual.Status.Should().Be(401);
        actual.Type.Should().Be(ProblemEnvelope.UnregisteredType);
        actual.Title.Should().Be("Webhook Signature Rejected");
        actual.Instance.Should().Be("/internal/webhooks/stripe");
        actual.Recoverable.Should().BeFalse();
        actual.Extensions!["traceId"].GetString().Should().Be("trace-6");
    }

    [Fact]
    public void It_should_write_data_as_an_empty_object_rather_than_omitting_it()
    {
        // Arrange — the published Problems TestHelper asserts all seven Diene members are
        // present, so omitting data would break a consumer's BeRfc9457 on this package's own
        // responses.
        var envelope = ProblemEnvelope.FromProtocol(421, "Misdirected", "Not mine.", "/x", "t");

        // Act
        var actual = JsonSerializer.Serialize(envelope, AtomiJson.DefaultOptions);

        // Assert
        actual.Should().Contain("\"data\":{}");
    }
}

public class ProblemEnvelope_ToResult
{
    [Fact]
    public void It_should_write_the_envelope_as_problem_json_at_its_own_status()
    {
        // Arrange
        var envelope = ProblemEnvelope.FromProtocol(415, "Unsupported", "Wrong media type.", "/x", "t");

        // Act
        var actual = ProblemEnvelope.ToResult(envelope);

        // Assert
        actual.StatusCode.Should().Be(415);
        actual.ContentType.Should().Be(ProblemEnvelope.ContentType);
        actual.Content.Should().Contain("\"status\":415");
    }

    [Fact]
    public void It_should_camel_case_every_member_and_omit_nulls()
    {
        // Arrange
        var envelope = ProblemEnvelope.FromDomain(
            new Unauthenticated("No token."),
            ProblemEnvelope_FromDomain.Catalog(),
            ProblemEnvelope_FromDomain.TypeUris(),
            "/x",
            "t");

        // Act
        var actual = ProblemEnvelope.ToResult(envelope).Content;

        // Assert
        actual.Should().Contain("\"recoverable\":true").And.Contain("\"traceId\":\"t\"");
        actual.Should().NotContain("Recoverable");
    }

    [Fact]
    public void It_should_reject_a_null_envelope()
    {
        // Act
        var act = () => ProblemEnvelope.ToResult(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }
}
