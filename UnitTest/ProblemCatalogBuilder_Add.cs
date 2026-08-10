using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;

namespace AtomiCloud.Diene.Problems.UnitTest;

public class ProblemCatalogBuilder_Add
{
    [Fact]
    public void It_should_register_direct_assembly_and_baseline_descriptors()
    {
        // Arrange
        var subject = new ProblemCatalogBuilder()
            .Add<OtherProblem>(409, true, new ProblemEndpoint("POST", "/other"))
            .AddFromAssembly(
                typeof(SampleProblem).Assembly,
                type => type == typeof(SampleProblem),
                _ => 422,
                _ => true,
                _ => [new ProblemEndpoint("GET", "/sample")])
            .AddBaseline();

        // Act
        var actual = subject.Build(NullLogger<ProblemCatalog>.Instance);

        // Assert
        actual.All.Should().HaveCount(9);
        actual.Find("v1", "sample_problem").Should().BeSome().Which.Status.Should().Be(422);
        actual.Find("v1", "missing").Should().BeNone();
        actual.StatusOf(new SampleProblem()).Should().Be(422);
        actual.All.Single(descriptor => descriptor.Id == "other_problem").Endpoints
            .Should().ContainSingle().Which.Should().Be(new ProblemEndpoint("POST", "/other"));
    }

    [Fact]
    public void It_should_support_an_empty_opt_in_assembly_scan_and_default_logger()
    {
        // Arrange
        var subject = new ProblemCatalogBuilder();

        // Act
        var actual = subject
            .AddFromAssembly(typeof(SampleProblem).Assembly, _ => false, _ => 400)
            .Build();

        // Assert
        actual.All.Should().BeEmpty();
    }

    [Fact]
    public void It_should_reject_duplicate_or_invalid_registration_metadata()
    {
        // Act
        var duplicate = () => new ProblemCatalogBuilder()
            .Add<SampleProblem>(400, false)
            .Add<SpoofedSampleProblem>(500, false);
        var status = () => new ProblemCatalogBuilder().Add<SampleProblem>(399, false);
        var id = () => new ProblemCatalogBuilder().Add<BadIdProblem>(400, false);
        var version = () => new ProblemCatalogBuilder().Add<BadVersionProblem>(400, false);
        var title = () => new ProblemCatalogBuilder().Add<BlankTitleProblem>(400, false);
        var method = () => new ProblemCatalogBuilder().Add<SampleProblem>(
            400,
            false,
            new ProblemEndpoint("get", "/sample"));
        var path = () => new ProblemCatalogBuilder().Add<SampleProblem>(
            400,
            false,
            new ProblemEndpoint("GET", "sample"));
        var endpoint = () => new ProblemCatalogBuilder().Add<SampleProblem>(400, false, null!);

        // Assert
        duplicate.Should().Throw<InvalidOperationException>();
        status.Should().Throw<ArgumentOutOfRangeException>();
        id.Should().Throw<ArgumentOutOfRangeException>();
        version.Should().Throw<ArgumentOutOfRangeException>();
        title.Should().Throw<ArgumentException>();
        method.Should().Throw<ArgumentException>();
        path.Should().Throw<ArgumentException>();
        endpoint.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_validate_required_assembly_scan_callbacks()
    {
        // Arrange
        var subject = new ProblemCatalogBuilder();

        // Act
        var assembly = () => subject.AddFromAssembly(null!, _ => true, _ => 400);
        var filter = () => subject.AddFromAssembly(typeof(SampleProblem).Assembly, null!, _ => 400);
        var status = () => subject.AddFromAssembly(typeof(SampleProblem).Assembly, _ => true, null!);

        // Assert
        assembly.Should().Throw<ArgumentNullException>();
        filter.Should().Throw<ArgumentNullException>();
        status.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_log_loudly_and_return_500_for_unknown_or_spoofed_types()
    {
        // Arrange
        var logger = new CapturingLogger<ProblemCatalog>();
        var subject = new ProblemCatalogBuilder().Add<SampleProblem>(418, false).Build(logger);

        // Act
        var unknownStatus = subject.StatusOf(new OtherProblem());
        var spoofedStatus = subject.StatusOf(new SpoofedSampleProblem());
        var nullAct = () => subject.StatusOf(null!);

        // Assert
        unknownStatus.Should().Be(500);
        spoofedStatus.Should().Be(500);
        logger.Messages.Should().HaveCount(2).And.OnlyContain(message => message.Contains("returning 500", StringComparison.Ordinal));
        nullAct.Should().Throw<ArgumentNullException>();
    }
}
