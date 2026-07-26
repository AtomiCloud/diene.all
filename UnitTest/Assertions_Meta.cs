using System.Net;
using System.Text;
using System.Text.Json;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.Results;
using FluentAssertions;

namespace AtomiCloud.Diene.Problems.UnitTest;

public class Assertions_Meta
{
    private static readonly string TypeUri =
        "https://docs.example.test/docs/lapras/dotnet/notes/api/v1/sample_problem";

    [Fact]
    public void It_should_accept_domain_identity_and_reject_known_bad_values()
    {
        // Arrange
        IDomainProblem subject = new SampleProblem("value");

        // Act
        var good = () =>
        {
            subject.Should().BeProblem<SampleProblem>();
            subject.Should().HaveId("sample_problem");
            subject.Should().HaveVersion("v1");
        };
        var wrongType = () => subject.Should().BeProblem<OtherProblem>();
        var wrongId = () => subject.Should().HaveId("wrong");
        var wrongVersion = () => subject.Should().HaveVersion("v2");

        // Assert
        good.Should().NotThrow();
        wrongType.Should().Throw<Exception>();
        wrongId.Should().Throw<Exception>();
        wrongVersion.Should().Throw<Exception>();
    }

    [Fact]
    public void It_should_accept_and_reject_exception_problem_types()
    {
        // Arrange
        Action act = () => throw new SampleProblem("value").ToException();

        // Act
        var good = () => act.Should().Throw<DomainProblemException>()
            .WithProblem<SampleProblem>(problem => problem.Value.Should().Be("value"));
        var bad = () => act.Should().Throw<DomainProblemException>().WithProblem<OtherProblem>();

        // Assert
        good.Should().NotThrow();
        bad.Should().Throw<Exception>();
    }

    [Fact]
    public void It_should_accept_envelope_fields_and_reject_known_bad_values()
    {
        // Arrange
        var subject = Envelope();

        // Act
        var good = () =>
        {
            subject.Should().HaveType(TypeUri);
            subject.Should().HaveStatus(422);
            subject.Should().HaveData(new SampleProblem("value"));
            subject.Should().BeRecoverable(true);
        };
        var type = () => subject.Should().HaveType("about:blank");
        var status = () => subject.Should().HaveStatus(500);
        var data = () => subject.Should().HaveData(new SampleProblem("wrong"));
        var absentData = () => (subject with { Data = null }).Should().HaveData(new SampleProblem("value"));
        var recoverable = () => subject.Should().BeRecoverable(false);

        // Assert
        good.Should().NotThrow();
        type.Should().Throw<Exception>();
        status.Should().Throw<Exception>();
        data.Should().Throw<Exception>();
        absentData.Should().Throw<Exception>();
        recoverable.Should().Throw<Exception>();
    }

    [Fact]
    public async Task It_should_accept_a_full_HTTP_problem_and_reject_non_problem_responses()
    {
        // Arrange
        using var goodResponse = Response(Envelope(), HttpStatusCode.UnprocessableEntity);
        using var wrongContentType = new HttpResponseMessage(HttpStatusCode.BadRequest)
        {
            Content = new StringContent("{}", Encoding.UTF8, "application/json"),
        };
        using var missingMembers = new HttpResponseMessage(HttpStatusCode.BadRequest)
        {
            Content = new StringContent("{\"type\":\"about:blank\"}", Encoding.UTF8, "application/problem+json"),
        };
        using var wrongStatus = Response(Envelope(), HttpStatusCode.InternalServerError);

        // Act
        var good = await goodResponse.Should().BeRfc9457();
        var contentTypeAct = async () => await wrongContentType.Should().BeRfc9457();
        var membersAct = async () => await missingMembers.Should().BeRfc9457();
        var statusAct = async () => await wrongStatus.Should().BeRfc9457();

        // Assert
        good.Which.Should().HaveType(TypeUri);
        await contentTypeAct.Should().ThrowAsync<Exception>();
        await membersAct.Should().ThrowAsync<Exception>();
        await statusAct.Should().ThrowAsync<Exception>();
    }

    [Fact]
    public void It_should_accept_err_problem_and_reject_ok_or_wrong_problem_results()
    {
        // Arrange
        var goodSubject = Result.Err<int, IDomainProblem>(new SampleProblem("bad"));
        var okSubject = Result.Ok<int, IDomainProblem>(42);
        var wrongSubject = Result.Err<int, IDomainProblem>(new OtherProblem());

        // Act
        var good = () => goodSubject.Should().BeErrProblem<SampleProblem>();
        var ok = () => okSubject.Should().BeErrProblem<SampleProblem>();
        var wrong = () => wrongSubject.Should().BeErrProblem<SampleProblem>();

        // Assert
        good.Should().NotThrow();
        ok.Should().Throw<Exception>();
        wrong.Should().Throw<Exception>();
    }

    [Fact]
    public async Task It_should_validate_null_assertion_subjects()
    {
        // Act
        var domain = () => new DomainProblemAssertions(null!);
        var envelope = () => new ProblemEnvelopeAssertions(null!);
        var response = async () => await HttpResponseProblemAssertions.BeRfc9457(null!);

        // Assert
        domain.Should().Throw<ArgumentNullException>();
        envelope.Should().Throw<ArgumentNullException>();
        await response.Should().ThrowAsync<ArgumentNullException>();
    }

    private static Problem Envelope() => new()
    {
        Type = TypeUri,
        Title = "Sample Problem",
        Status = 422,
        Detail = "sample detail",
        Instance = "/sample/value",
        Recoverable = true,
        Data = JsonSerializer.SerializeToNode(new SampleProblem("value"), AtomiJson.DefaultOptions),
    };

    private static HttpResponseMessage Response(Problem problem, HttpStatusCode status) => new(status)
    {
        Content = new StringContent(
            JsonSerializer.Serialize(problem, AtomiJson.DefaultOptions),
            Encoding.UTF8,
            "application/problem+json"),
    };
}
