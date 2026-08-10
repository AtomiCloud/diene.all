using AtomiCloud.Diene.AuthEngine.Config;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Config;

public class HandoffConfig_Create
{
    [Fact]
    public void Defaults_to_the_documented_mount()
    {
        HandoffConfig.Default.Mount.Should().Be("/app-handoff");
        HandoffConfig.DefaultMount.Should().Be("/app-handoff");
    }

    [Theory]
    [InlineData("/app-handoff")]
    [InlineData("/auth/handoff")]
    [InlineData("/a")]
    public void Accepts_an_absolute_unencoded_path(string mount) =>
        HandoffConfig.Create(mount).Get().Mount.Should().Be(mount);

    [Fact]
    public void Trims_surrounding_whitespace()
    {
        HandoffConfig.Create("  /app-handoff  ").Get().Mount.Should().Be("/app-handoff");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("    ")]
    public void Rejects_a_blank_mount(string? mount) =>
        HandoffConfig.Create(mount).GetFailure().Reason.Should().Contain("must not be blank");

    [Fact]
    public void Rejects_a_relative_mount() =>
        HandoffConfig.Create("app-handoff").GetFailure().Reason.Should().Contain("absolute path");

    [Fact]
    public void Rejects_an_empty_segment() =>
        HandoffConfig.Create("/app//handoff").GetFailure().Reason.Should().Contain("empty segment");

    [Theory]
    [InlineData("/app\\handoff")]
    [InlineData("/app?x=1")]
    [InlineData("/app#frag")]
    [InlineData("/app%2Fhandoff")]
    public void Rejects_a_mount_carrying_a_backslash_query_fragment_or_encoding(string mount) =>
        HandoffConfig.Create(mount).GetFailure().Reason.Should()
            .Contain("backslash, query, fragment, or percent-encoding");

    [Fact]
    public void Rejects_internal_whitespace() =>
        HandoffConfig.Create("/app handoff").GetFailure().Reason.Should().Contain("whitespace");

    [Theory]
    [InlineData("/../etc")]
    [InlineData("/app/../../etc")]
    [InlineData("/app/./handoff")]
    public void Rejects_dot_path_traversal(string mount) =>
        HandoffConfig.Create(mount).GetFailure().Reason.Should().Contain("dot-path traversal");
}
