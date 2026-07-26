namespace AtomiCloud.DotnetBase.UnitTest;

public class AppIdentityTests
{
    [Fact]
    public void Create_TrimsEveryField() =>
        AppIdentity
            .Create(" lapras ", " atomi ", " billing ", " api ", " 1.2.3 ")
            .Should().BeOk()
            .Which.Should().Be(new AppIdentity("lapras", "atomi", "billing", "api", "1.2.3"));

    [Theory]
    [InlineData(null, "atomi", "billing", "api", "1.0.0")]
    [InlineData("", "atomi", "billing", "api", "1.0.0")]
    [InlineData("  ", "atomi", "billing", "api", "1.0.0")]
    [InlineData("lapras", " ", "billing", "api", "1.0.0")]
    [InlineData("lapras", "atomi", " ", "api", "1.0.0")]
    [InlineData("lapras", "atomi", "billing", " ", "1.0.0")]
    [InlineData("lapras", "atomi", "billing", "api", " ")]
    public void Create_RejectsAnyBlankField(
        string? landscape,
        string? platform,
        string? service,
        string? module,
        string? version) =>
        AppIdentity
            .Create(landscape, platform, service, module, version)
            .Should().BeErr()
            .Which.Id.Should().Be("invalid_argument");

    [Fact]
    public void Create_NamesTheFieldItRejected() =>
        AppIdentity
            .Create("lapras", "atomi", "billing", " ", "1.0.0")
            .Should().BeErr()
            .Which.Detail.Should().Contain("module");

    [Fact]
    public void Identity_HasValueEquality()
    {
        var left = new AppIdentity("lapras", "atomi", "billing", "api", "1.0.0");
        var right = new AppIdentity("lapras", "atomi", "billing", "api", "1.0.0");
        left.Should().Be(right);
        left.GetHashCode().Should().Be(right.GetHashCode());
        left.Should().NotBe(right with { Module = "worker" });
    }
}
