namespace AtomiCloud.DotnetBase.UnitTest;

public class ConfigKeyTests
{
    [Theory]
    [InlineData("error_portal", "errorportal")]
    [InlineData("error-portal", "errorportal")]
    [InlineData("errorPortal", "errorportal")]
    [InlineData("ErrorPortal", "errorportal")]
    [InlineData("ERROR_PORTAL", "errorportal")]
    public void Segment_collapses_every_C0_spelling_onto_one_key(string spelling, string canonical) =>
        ConfigKey.Segment(spelling).Should().Be(canonical);

    [Fact]
    public void Path_canonicalises_each_segment_and_keeps_the_delimiters() =>
        ConfigKey.Path("Error_Portal:Retry-Hosts:0").Should().Be("errorportal:retryhosts:0");

    [Fact]
    public void Path_leaves_an_already_canonical_path_alone() =>
        ConfigKey.Path("errorportal:host").Should().Be("errorportal:host");

    [Fact]
    public void Path_rejects_a_null_path() =>
        FluentActions.Invoking(() => ConfigKey.Path(null!)).Should().Throw<ArgumentNullException>();
}
