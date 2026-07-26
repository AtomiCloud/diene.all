using FluentAssertions;

namespace AtomiCloud.Diene.Problems.UnitTest;

public class ProblemTypeUriBuilder_Build
{
    public static TheoryData<ErrorPortalConfig, string, string> InvalidInputs => new()
    {
        { Config(scheme: "ftp"), "v1", "sample_problem" },
        { Config(host: " docs.example.test"), "v1", "sample_problem" },
        { Config(host: "docs.example.test/path"), "v1", "sample_problem" },
        { Config(host: "User@docs.example.test"), "v1", "sample_problem" },
        { Config(host: "docs.example.test:notaport"), "v1", "sample_problem" },
        { Config(landscape: "bad/value"), "v1", "sample_problem" },
        { Config(platform: ""), "v1", "sample_problem" },
        { Config(service: "bad value"), "v1", "sample_problem" },
        { Config(module: "?"), "v1", "sample_problem" },
        { Config(), "V1", "sample_problem" },
        { Config(), "v1", "sample-problem" },
        { Config(), "v1", "SampleProblem" },
    };

    [Fact]
    public void It_should_expand_every_identity_segment_and_version()
    {
        // Arrange
        var subject = new ProblemTypeUriBuilder(Config(host: "docs.example.test:8443"));

        // Act
        var actual = subject.Build("v12", "sample_problem");

        // Assert
        actual.AbsoluteUri.Should().Be(
            "https://docs.example.test:8443/docs/lapras/dotnet/notes/api/v12/sample_problem");
    }

    [Theory]
    [MemberData(nameof(InvalidInputs))]
    public void It_should_reject_invalid_portal_or_problem_segments(
        ErrorPortalConfig config,
        string version,
        string id)
    {
        // Act
        var act = () => new ProblemTypeUriBuilder(config).Build(version, id);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Fact]
    public void It_should_reject_a_null_config_or_identity()
    {
        // Act
        var nullConfig = () => new ProblemTypeUriBuilder(null!);
        var nullIdentity = () => new ProblemTypeUriBuilder(new ErrorPortalConfig("https", "docs.example.test", null!));

        // Assert
        nullConfig.Should().Throw<ArgumentNullException>();
        nullIdentity.Should().Throw<ArgumentNullException>();
    }

    private static ErrorPortalConfig Config(
        string scheme = "https",
        string host = "docs.example.test",
        string landscape = "lapras",
        string platform = "dotnet",
        string service = "notes",
        string module = "api") =>
        new(scheme, host, new ProblemIdentity(landscape, platform, service, module));
}
