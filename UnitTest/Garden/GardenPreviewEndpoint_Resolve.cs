using AtomiCloud.Diene.E2e.Garden;
using FluentAssertions;

namespace AtomiCloud.Diene.E2e.UnitTest.Garden;

public class GardenPreviewEndpoint_Resolve
{
    private static GardenNamespaceFixture Fixture => new(
        "api",
        "notes",
        "sulfoxide",
        "pichu",
        "mew",
        "cluster.atomi.cloud");

    [Fact]
    public void It_should_resolve_the_final_https_hostname()
    {
        var actual = GardenPreviewEndpoint.Resolve(Fixture.Hostname, Fixture);

        actual.Should().Be(new Uri("https://api.notes.sulfoxide.pichu.mew.cluster.atomi.cloud/"));
    }

    [Fact]
    public void It_should_preserve_an_explicit_http_port_and_path()
    {
        var actual = GardenPreviewEndpoint.Resolve(
            Fixture.Hostname,
            Fixture,
            "http",
            8080,
            "/system/health");

        actual.Should().Be(
            new Uri("http://api.notes.sulfoxide.pichu.mew.cluster.atomi.cloud:8080/system/health"));
    }

    [Fact]
    public void It_should_refuse_a_hostname_from_a_different_namespace()
    {
        var act = () => GardenPreviewEndpoint.Resolve(
            "api.notes.sulfoxide.raichu.mew.cluster.atomi.cloud",
            Fixture);

        act.Should().Throw<E2eHarnessException>().WithMessage("*expected*");
    }

    [Theory]
    [InlineData("")]
    [InlineData("Api.notes.sulfoxide.pichu.mew.cluster.atomi.cloud")]
    [InlineData("-api.notes.sulfoxide.pichu.mew.cluster.atomi.cloud")]
    [InlineData("api..sulfoxide.pichu.mew.cluster.atomi.cloud")]
    public void It_should_refuse_an_invalid_hostname(string hostname)
    {
        var act = () => GardenPreviewEndpoint.Resolve(hostname, Fixture);

        act.Should().Throw<E2eHarnessException>().WithMessage("*lowercase DNS name*");
    }

    [Fact]
    public void It_should_refuse_an_invalid_fixture()
    {
        var fixture = Fixture with { Zone = "Cluster.Atomi.Cloud" };

        var act = () => GardenPreviewEndpoint.Resolve(fixture.Hostname, fixture);

        act.Should().Throw<E2eHarnessException>().WithMessage("fixture*");
    }

    [Fact]
    public void It_should_refuse_a_null_fixture()
    {
        var act = () => GardenPreviewEndpoint.Resolve(Fixture.Hostname, null!);

        act.Should().Throw<ArgumentNullException>();
    }

    [Theory]
    [InlineData("ftp", null, "/")]
    [InlineData("https", 0, "/")]
    [InlineData("https", 65536, "/")]
    [InlineData("https", null, "relative")]
    [InlineData("https", null, "//authority")]
    public void It_should_refuse_an_ambiguous_endpoint(string scheme, int? port, string path)
    {
        var act = () => GardenPreviewEndpoint.Resolve(Fixture.Hostname, Fixture, scheme, port, path);

        act.Should().Throw<E2eHarnessException>();
    }
}
