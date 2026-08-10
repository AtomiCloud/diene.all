using AtomiCloud.Diene.Interfaces.App;
using AtomiCloud.Diene.Interfaces.App.Adapters;

namespace AtomiCloud.Diene.Interfaces.IntTest;

/// <summary>
/// INT tier — CONTRACT PARITY, real-implementation half. The SAME
/// <see cref="SeamContracts"/> suites the meta tier runs against the shipped
/// in-memory mocks are run here against host-backed adapters that touch a real
/// filesystem, a real process, and the real process environment. A seam is only
/// substitutable if both halves are conformant.
/// </summary>
public class HostSeamContractTests : IDisposable
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    private readonly string _root = Path.Combine(
        Path.GetTempPath(),
        $"diene-interfaces-int-{Guid.NewGuid():N}");

    public HostSeamContractTests() => Directory.CreateDirectory(_root);

    public void Dispose()
    {
        if (Directory.Exists(_root)) Directory.Delete(_root, true);
        GC.SuppressFinalize(this);
    }

    [Fact]
    public async Task The_host_vfs_should_satisfy_the_vfs_contract()
    {
        var report = await SeamContracts.Vfs(new HostVfs(), _root);

        report.Seam.Should().Be(SeamKind.Vfs);
        report.Should().BeConformant();
    }

    [Fact]
    public async Task The_host_system_should_satisfy_the_system_contract()
    {
        var present = $"DIENE_INT_{Guid.NewGuid():N}";
        var absent = $"DIENE_INT_ABSENT_{Guid.NewGuid():N}";
        Environment.SetEnvironmentVariable(present, "yes");
        try
        {
            var report = await SeamContracts.System(new HostSystem(), present, "yes", absent);

            report.Seam.Should().Be(SeamKind.System);
            report.Should().BeConformant();
        }
        finally
        {
            Environment.SetEnvironmentVariable(present, null);
        }
    }

    [Fact]
    public async Task The_host_terminal_should_satisfy_the_terminal_contract()
    {
        var report = await SeamContracts.Terminal(
            new HostTerminal(),
            new TerminalCommand("sh", ["-c", "printf hello"]),
            "hello",
            new TerminalCommand("sh", ["-c", "exit 3"]),
            new TerminalCommand($"diene-absent-{Guid.NewGuid():N}"));

        report.Seam.Should().Be(SeamKind.Terminal);
        report.Should().BeConformant();
    }

    [Fact]
    public async Task The_host_sinks_should_satisfy_the_emit_contracts()
    {
        await using var writer = new StringWriter();

        var logger = await SeamContracts.LoggerSink(new TextWriterLoggerSink(writer), Anchor);
        var metrics = await SeamContracts.MetricsCollector(new TextWriterMetricsCollector(writer), Anchor);

        logger.Should().BeConformant();
        metrics.Should().BeConformant();
        writer.ToString().Should().Contain("contract");
    }

    [Fact]
    public async Task The_host_sinks_should_report_a_closed_destination_as_a_failure_value()
    {
        var writer = new StringWriter();
        await writer.DisposeAsync();

        new TextWriterLoggerSink(writer).Emit(new LogRecord(Anchor, LogLevel.Info, "closed"))
            .Should().BeSeamErr(SeamKind.Logging, "emit_failed");
        new TextWriterMetricsCollector(writer).Emit(new MetricRecord(Anchor, "closed", MetricKind.Counter, 1))
            .Should().BeSeamErr(SeamKind.Metrics, "emit_failed");
    }

    [Fact]
    public void The_host_sinks_should_reject_a_null_record()
    {
        new TextWriterLoggerSink(TextWriter.Null).Emit(null!)
            .Should().BeSeamErr(SeamKind.Logging, "invalid_argument");
        new TextWriterMetricsCollector(TextWriter.Null).Emit(null!)
            .Should().BeSeamErr(SeamKind.Metrics, "invalid_argument");
    }

    [Fact]
    public async Task The_host_vfs_should_reject_a_blank_path()
    {
        var vfs = new HostVfs();
        var token = TestContext.Current.CancellationToken;

        (await vfs.Exists("  ", token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.ReadText("  ", token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.WriteText("  ", "x", default, token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.List("  ", default, token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.CreateDirectory("  ", default, token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.Delete("  ", default, token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Fact]
    public async Task The_host_vfs_should_report_a_symbolic_link_as_a_link_entry()
    {
        var target = Path.Combine(_root, "target.txt");
        var link = Path.Combine(_root, "link.txt");
        (await new HostVfs().WriteText(target, "hello", default, TestContext.Current.CancellationToken))
            .Should().BeOk();
        File.CreateSymbolicLink(link, target);

        var entries = (await new HostVfs().List(_root, default, TestContext.Current.CancellationToken))
            .Should().BeOk().Which;

        entries.Should().Contain(entry => entry.Type == VfsEntryType.Link);
        entries.Should().Contain(entry => entry.Type == VfsEntryType.File);
    }

    [Fact]
    public async Task The_host_system_should_report_a_cancelled_delay_as_a_failure_value()
    {
        using var cancelled = new CancellationTokenSource();
        await cancelled.CancelAsync();

        (await new HostSystem().Delay(TimeSpan.FromSeconds(30), cancelled.Token))
            .Should().BeSeamErr(SeamKind.System, "cancelled");
    }

    [Fact]
    public async Task The_host_system_should_reject_a_blank_variable_name()
    {
        new HostSystem().Environment("  ").Should().BeSeamErr(SeamKind.System, "invalid_argument");
        new HostSystem().CurrentDirectory().Should().BeOk();
        new HostSystem().NowUtc().Should().BeOk().Which.Offset.Should().Be(TimeSpan.Zero);
        (await new HostSystem().Delay(TimeSpan.Zero, TestContext.Current.CancellationToken)).Should().BeOk();
    }

    [Fact]
    public async Task The_host_terminal_should_reject_a_null_command()
    {
        (await new HostTerminal().Run(null!, TestContext.Current.CancellationToken))
            .Should().BeSeamErr(SeamKind.Terminal, "invalid_argument");
    }

    [Fact]
    public async Task The_host_terminal_should_honour_a_command_environment_and_working_directory()
    {
        var result = await new HostTerminal().Run(
            new TerminalCommand(
                "sh",
                ["-c", "printf \"$DIENE_INT_VALUE:$(pwd)\""],
                _root,
                [new("DIENE_INT_VALUE", "carried")]),
            TestContext.Current.CancellationToken);

        result.Should().BeOk().Which.Stdout.Should().StartWith("carried:");
    }

    [Fact]
    public void The_demo_consumer_should_exercise_the_published_surface_against_the_host()
    {
        var act = Samples.RunAll;

        act.Should().NotThrow();
    }
}
