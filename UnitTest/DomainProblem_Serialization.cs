using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;

namespace AtomiCloud.Diene.Problems.UnitTest;

public class DomainProblem_Serialization
{
    [Fact]
    public void It_should_serialize_only_typed_payload_and_round_trip_the_wire_envelope()
    {
        // Arrange
        IDomainProblem domain = new SampleProblem("payload");
        var envelope = new Problem
        {
            Type = "https://docs.example.test/docs/lapras/dotnet/notes/api/v1/sample_problem",
            Title = domain.Title,
            Status = 422,
            Detail = domain.Detail,
            Instance = "/sample/1",
            Data = JsonSerializer.SerializeToNode(domain, domain.GetType(), AtomiJson.DefaultOptions),
            Recoverable = true,
            Extensions = new Dictionary<string, JsonElement>
            {
                ["traceId"] = JsonSerializer.SerializeToElement("trace-1"),
            },
        };

        // Act
        var payload = envelope.Data!.AsObject();
        var json = JsonSerializer.Serialize(envelope, AtomiJson.DefaultOptions);
        var actual = JsonSerializer.Deserialize<Problem>(json, AtomiJson.DefaultOptions);

        // Assert
        payload.Select(property => property.Key).Should().Equal("value");
        actual.Should().NotBeNull();
        actual!.Type.Should().Be(envelope.Type);
        actual.Title.Should().Be(envelope.Title);
        actual.Status.Should().Be(envelope.Status);
        actual.Detail.Should().Be(envelope.Detail);
        actual.Instance.Should().Be(envelope.Instance);
        actual.Recoverable.Should().Be(envelope.Recoverable);
        JsonNode.DeepEquals(actual.Data, envelope.Data).Should().BeTrue();
        actual.Extensions.Should().ContainKey("traceId");
        actual.Extensions!["traceId"].GetString().Should().Be("trace-1");
        json.Should().Contain("\"recoverable\":true").And.Contain("\"traceId\":\"trace-1\"");
    }

    [Fact]
    public void It_should_exercise_exception_result_and_guard_boundaries()
    {
        // Arrange
        IDomainProblem problem = new SampleProblem("bad");

        // Act
        var exception = problem.ToException();
        var failure = problem.ToErr<string>();
        var present = ProblemGuard.NotNull("ok", () => problem);
        var missing = ProblemGuard.NotNull<string>(null, () => problem);
        var required = ProblemGuard.Require(true, () => problem);
        var rejected = ProblemGuard.Require(false, () => problem);
        var found = ProblemGuard.NotFound("value", "id");
        var notFound = ProblemGuard.NotFound<string>(null, "id");

        // Assert
        exception.Problem.Should().BeSameAs(problem);
        exception.Message.Should().Be(problem.Detail);
        failure.Should().BeErr().Which.Should().BeSameAs(problem);
        present.Should().BeOk("ok");
        missing.Should().BeErr().Which.Should().BeSameAs(problem);
        required.Should().BeOk();
        rejected.Should().BeErr().Which.Should().BeSameAs(problem);
        found.Should().BeOk("value");
        notFound.Should().BeErr().Which.Should().BeOfType<EntityNotFound>();
    }

    [Fact]
    public void It_should_reject_null_exception_result_and_guard_inputs()
    {
        // Act
        var exception = () => new DomainProblemException(null!);
        var result = () => DomainProblemExtensions.ToErr<string>(null!);
        var notNull = () => ProblemGuard.NotNull("value", null!);
        var require = () => ProblemGuard.Require(true, null!);

        // Assert
        exception.Should().Throw<ArgumentNullException>();
        result.Should().Throw<ArgumentNullException>();
        notNull.Should().Throw<ArgumentNullException>();
        require.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_pin_baseline_metadata_payloads_and_R_E14_wire_casing()
    {
        // Arrange
        IDomainProblem[] subjects =
        [
            new EntityNotFound("missing", typeof(string), "one"),
            new MultipleEntityNotFound("missing many", typeof(string), ["one"], ["two"]),
            new EntityConflict("conflict", typeof(string)),
            new ValidationError("invalid", new Dictionary<string, string[]> { ["name"] = ["required"] }),
            new Unauthorized("forbidden", ["read"], ["write"]),
            new Unauthenticated("sign in"),
            new InvalidJson("invalid", "{")
        ];

        // Act
        var metadata = subjects.Select(subject => (subject.Id, subject.Title, subject.Detail, subject.Version)).ToArray();

        // Assert
        metadata.Select(value => value.Id).Should().Equal(
            "entity_not_found",
            "multiple_entity_not_found",
            "entity_conflict",
            "validation_error",
            "unauthorized",
            "unauthenticated",
            "invalid_json");
        metadata.Should().OnlyContain(value => value.Version == "v1" && value.Title.Length > 0 && value.Detail.Length > 0);
        nameof(EntityNotFound).Should().Be("EntityNotFound");
        subjects[0].Id.Should().Be("entity_not_found");

        var entity = (EntityNotFound)subjects[0];
        entity.RequestIdentifier.Should().Be("one");
        entity.TypeName.Should().Be(typeof(string).FullName);
        entity.AssemblyQualifiedName.Should().Be(typeof(string).AssemblyQualifiedName);
        ((MultipleEntityNotFound)subjects[1]).RequestIdentifiers.Should().Equal("one");
        ((MultipleEntityNotFound)subjects[1]).FoundRequestIdentifiers.Should().Equal("two");
        ((EntityConflict)subjects[2]).TypeName.Should().Be(typeof(string).FullName);
        ((ValidationError)subjects[3]).Errors.Should().ContainKey("name");
        ((Unauthorized)subjects[4]).Granted.Should().Equal("read");
        ((Unauthorized)subjects[4]).Required.Should().Equal("write");
        ((InvalidJson)subjects[6]).InvalidString.Should().Be("{");
        new OtherProblem().Code.Should().Be(7);
    }

    [Fact]
    public void It_should_keep_the_neutral_C0_fixture_byte_exact_and_record_the_kebab_variance()
    {
        // Arrange
        var path = Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "problem-v1.json");
        var bytes = File.ReadAllBytes(path);

        // Act
        var hash = Convert.ToHexStringLower(SHA256.HashData(bytes));
        using var fixture = JsonDocument.Parse(bytes);
        var fixtureId = fixture.RootElement.GetProperty("cases").GetProperty("typeUri")
            .GetProperty("valid")[0].GetProperty("segments").GetProperty("id").GetString();

        // Assert
        hash.Should().Be("a8c02554c198627df9badc6c2377218556ec8bd3a0b1edcdb20aedeebe43f988");
        fixtureId.Should().Be("entity-not-found");
        new EntityNotFound().Id.Should().Be("entity_not_found", "R-E14 supersedes the fixture's kebab sample");
    }

    [Fact]
    public void It_should_expose_the_engine_owned_portal_block_defaults_and_mutability()
    {
        // Arrange
        var defaults = new ErrorPortalOption();
        var subject = new ErrorPortalOption
        {
            Enabled = false,
            Scheme = "http",
            Host = "localhost:8080",
        };

        // Act
        var actual = (subject.Enabled, subject.Scheme, subject.Host);

        // Assert
        ErrorPortalOption.Key.Should().Be("ErrorPortal");
        defaults.Enabled.Should().BeTrue();
        defaults.Scheme.Should().Be("https");
        actual.Should().Be((false, "http", "localhost:8080"));
    }
}
