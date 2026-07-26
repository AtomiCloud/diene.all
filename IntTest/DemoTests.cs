namespace AtomiCloud.DotnetBase.IntTest;

/// <summary>Drives the demo consumer through its real entry point.</summary>
public class DemoTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("diene-config-demo").FullName;

    [Fact]
    public void The_demo_reports_every_step_of_the_layering_contract()
    {
        var lines = Demo.Run();

        lines.Should().Contain(line => line.Contains("error_portal.scheme = https", StringComparison.Ordinal));
        lines.Should().Contain(line => line.Contains("docs.lapras.atomi.cloud", StringComparison.Ordinal));
        lines.Should().Contain(line => line.Contains("injected-by-the-landscape", StringComparison.Ordinal));
        lines.Should().Contain(line => line.Contains("docs-fallback.atomi.cloud", StringComparison.Ordinal));
        lines.Should().NotContain(line => line.Contains("this is a defect", StringComparison.Ordinal));
    }

    [Fact]
    public void Running_with_no_arguments_succeeds() => Program.Main([]).Should().Be(0);

    [Fact]
    public void The_schema_task_writes_and_then_verifies_clean()
    {
        var path = Path.Combine(_directory, "settings.schema.json");

        Program.Main(["schema", "write", path]).Should().Be(0);
        Program.Main(["schema", "verify", path]).Should().Be(0);
    }

    [Fact]
    public void The_schema_task_reds_on_drift()
    {
        var path = Path.Combine(_directory, "drifted.schema.json");
        File.WriteAllText(path, "{}");

        Program.Main(["schema", "verify", path]).Should().Be(1);
    }

    [Fact]
    public void An_incomplete_schema_command_reports_usage() => Program.Main(["schema"]).Should().Be(2);

    [Fact]
    public void An_unknown_command_reports_usage() => Program.Main(["nonsense"]).Should().Be(2);

    [Fact]
    public void Main_rejects_a_null_argument_array() =>
        FluentActions.Invoking(() => Program.Main(null!)).Should().Throw<ArgumentNullException>();

    public void Dispose()
    {
        Directory.Delete(_directory, recursive: true);
        GC.SuppressFinalize(this);
    }
}
