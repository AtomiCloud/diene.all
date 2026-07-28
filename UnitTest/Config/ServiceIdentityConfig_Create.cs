using AtomiCloud.Diene.ServerEngine.Config;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Config;

public class ServiceIdentityConfig_Create
{
    [Fact]
    public void It_should_accept_and_trim_valid_coordinates()
    {
        // Arrange
        const string version = "  1.2.3+build.5  ";

        // Act
        var actual = ServiceIdentityConfig.Create(" lapras ", "sulfoxide", "demo", "api", version).Get();

        // Assert
        actual.Landscape.Should().Be("lapras");
        actual.Platform.Should().Be("sulfoxide");
        actual.Service.Should().Be("demo");
        actual.Module.Should().Be("api");
        actual.Version.Should().Be("1.2.3+build.5");
    }

    [Theory]
    [ClassData(typeof(BlankCoordinateCases))]
    public void It_should_reject_a_blank_coordinate(string? landscape, string? platform, string field)
    {
        // Act
        var actual = ServiceIdentityConfig.Create(landscape, platform, "demo", "api", "1.0.0");

        // Assert
        actual.GetFailure().Field.Should().Be(field);
        actual.GetFailure().Reason.Should().Contain("must not be blank");
    }

    [Theory]
    [ClassData(typeof(MalformedSegmentCases))]
    public void It_should_reject_a_segment_that_is_not_service_tree_shaped(string value)
    {
        // Act
        var actual = ServiceIdentityConfig.Create("lapras", "sulfoxide", value, "api", "1.0.0");

        // Assert
        actual.GetFailure().Field.Should().Be("identity.service");
        actual.GetFailure().Reason.Should().Contain("start alphanumeric");
    }

    [Theory]
    [ClassData(typeof(BlankVersionCases))]
    public void It_should_reject_a_blank_version(string? version)
    {
        // Act
        var actual = ServiceIdentityConfig.Create("lapras", "sulfoxide", "demo", "api", version);

        // Assert
        actual.GetFailure().Field.Should().Be("identity.version");
        actual.GetFailure().Reason.Should().Contain("must not be blank");
    }

    [Fact]
    public void It_should_name_the_first_failing_coordinate_only()
    {
        // Arrange — landscape and module are both invalid; the earlier one is reported.
        // Act
        var actual = ServiceIdentityConfig.Create(null, "sulfoxide", "demo", "-bad", "1.0.0");

        // Assert
        actual.GetFailure().Field.Should().Be("identity.landscape");
    }

    private sealed class BlankCoordinateCases : TheoryData<string?, string?, string>
    {
        public BlankCoordinateCases()
        {
            this.Add(null, "sulfoxide", "identity.landscape");
            this.Add(string.Empty, "sulfoxide", "identity.landscape");
            this.Add("   ", "sulfoxide", "identity.landscape");
            this.Add("lapras", null, "identity.platform");
            this.Add("lapras", "  ", "identity.platform");
        }
    }

    private sealed class MalformedSegmentCases : TheoryData<string>
    {
        public MalformedSegmentCases()
        {
            this.Add("-leading-dash");
            this.Add("_leading-underscore");
            this.Add(".leading-dot");
            this.Add("has space");
            this.Add("has/slash");
            this.Add("has:colon");
        }
    }

    private sealed class BlankVersionCases : TheoryData<string?>
    {
        public BlankVersionCases()
        {
            this.Add(null!);
            this.Add(string.Empty);
            this.Add("\t ");
        }
    }
}
