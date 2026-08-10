using System.Text.Json;
using FluentAssertions;

namespace AtomiCloud.Diene.Problems.IntTest;

public class C0Fixture_RoundTrip
{
    [Fact]
    public void It_should_pin_envelope_extensions_catalog_shape_and_snake_case_URI_expansion()
    {
        // Arrange
        var path = Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "problem-v1.json");
        using var fixture = JsonDocument.Parse(File.ReadAllBytes(path));
        var cases = fixture.RootElement.GetProperty("cases");
        var vector = cases.GetProperty("typeUri").GetProperty("valid")[0];
        var segments = vector.GetProperty("segments");
        var snakeId = segments.GetProperty("id").GetString()!.Replace('-', '_');
        var identity = new ProblemIdentity(
            segments.GetProperty("landscape").GetString()!,
            segments.GetProperty("platform").GetString()!,
            segments.GetProperty("service").GetString()!,
            segments.GetProperty("module").GetString()!);
        var subject = new ProblemTypeUriBuilder(new ErrorPortalConfig(
            segments.GetProperty("scheme").GetString()!,
            segments.GetProperty("host").GetString()!,
            identity));

        // Act
        var actual = subject.Build(segments.GetProperty("version").GetString()!, snakeId);
        var members = cases.GetProperty("rfc9457Members").EnumerateArray().Select(value => value.GetString()).ToArray();
        var extensions = cases.GetProperty("extensions").EnumerateArray().Select(value => value.GetString()).ToArray();
        var shape = cases.GetProperty("catalogEntry").GetProperty("shape")
            .EnumerateArray().Select(value => value.GetString()).ToArray();

        // Assert
        actual.AbsoluteUri.Should().Be(
            "https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api/v1/entity_not_found");
        members.Should().Equal("type", "title", "status", "detail", "instance");
        extensions.Should().Equal("data", "recoverable");
        shape.Should().Equal("id", "type", "title", "status", "recoverable", "data", "endpoints");
    }
}
