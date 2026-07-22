using System.Text.Json;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.App;
using FluentAssertions;

namespace AtomiCloud.Diene.Results.IntTest;

public class C0Fixture_RoundTrip
{
    [Fact]
    public void It_should_round_trip_the_versioned_source_fixture()
    {
        var fixturePath = Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "monad-v1.json");
        using var document = JsonDocument.Parse(File.ReadAllText(fixturePath));
        var expected = document.RootElement.GetProperty("cases");

        Equivalent(Result.Ok<int, string>(42).ToSerial(), expected.GetProperty("ok")).Should().BeTrue();
        Equivalent(Result.Err<int, string>("boom").ToSerial(), expected.GetProperty("err")).Should().BeTrue();
        Equivalent(Option.Some("value").ToSerial(), expected.GetProperty("some")).Should().BeTrue();
        Equivalent(Option.None<string>().ToSerial(), expected.GetProperty("none")).Should().BeTrue();
    }

    [Fact]
    public void It_should_run_the_package_consumer_sample()
    {
        using var output = new StringWriter();
        var original = Console.Out;
        try
        {
            Console.SetOut(output);
            Program.Main();
        }
        finally
        {
            Console.SetOut(original);
        }

        output.ToString().Trim().Should().Be("Success: 42");
    }

    private static bool Equivalent<T>(T value, JsonElement expected) =>
        JsonElement.DeepEquals(JsonDocument.Parse(JsonSerializer.Serialize(value)).RootElement, expected);
}
