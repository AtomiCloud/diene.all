using AtomiCloud.Diene.Problems.App;
using FluentAssertions;

namespace AtomiCloud.Diene.Problems.IntTest;

[Collection("Console")]
public class Program_Smoke
{
    [Fact]
    public async Task It_should_run_the_full_API_demo_serve_once_and_exit()
    {
        // Arrange
        var original = Console.Out;
        using var output = new StringWriter();
        Console.SetOut(output);

        try
        {
            // Act
            var exitCode = await Program.Main([]);

            // Assert
            exitCode.Should().Be(0);
            output.ToString().Should().Contain("problems;").And.Contain("\"type\":");
        }
        finally
        {
            Console.SetOut(original);
        }
    }
}

[CollectionDefinition("Console", DisableParallelization = true)]
public sealed class ConsoleCollection;
