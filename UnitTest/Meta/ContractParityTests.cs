namespace AtomiCloud.Diene.Interfaces.UnitTest.Meta;

/// <summary>
/// META tier — subject is the shipped TestHelper. This is the CONTRACT PARITY half:
/// the same <see cref="SeamContracts"/> suites the integration tier runs against
/// host-backed adapters are run here against the in-memory mocks, so a consumer
/// swapping the mock in gets identical behaviour.
/// </summary>
public class ContractParityTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    [Fact]
    public async Task The_in_memory_vfs_should_satisfy_the_vfs_contract()
    {
        var report = await SeamContracts.Vfs(new InMemoryVfs(Anchor), "/root");

        report.Seam.Should().Be(SeamKind.Vfs);
        report.Should().BeConformant();
    }

    [Fact]
    public async Task The_in_memory_system_should_satisfy_the_system_contract()
    {
        var system = new InMemorySystem(Anchor, "/work", [new("DIENE_PRESENT", "yes")]);

        var report = await SeamContracts.System(system, "DIENE_PRESENT", "yes", "DIENE_ABSENT");

        report.Seam.Should().Be(SeamKind.System);
        report.Should().BeConformant();
    }

    [Fact]
    public async Task The_in_memory_terminal_should_satisfy_the_terminal_contract()
    {
        var terminal = new InMemoryTerminal();
        terminal.Program("diene-ok", new TerminalOutput(0, "hello", string.Empty));
        terminal.Program("diene-fail", new TerminalOutput(3, string.Empty, "boom"));

        var report = await SeamContracts.Terminal(
            terminal,
            new TerminalCommand("diene-ok"),
            "hello",
            new TerminalCommand("diene-fail"),
            new TerminalCommand("diene-missing"));

        report.Seam.Should().Be(SeamKind.Terminal);
        report.Should().BeConformant();
        terminal.Commands.Should().HaveCount(3);
    }

    [Fact]
    public async Task The_in_memory_logger_sink_should_satisfy_the_logging_contract()
    {
        var sink = new InMemoryLoggerSink();

        var report = await SeamContracts.LoggerSink(sink, Anchor);

        report.Seam.Should().Be(SeamKind.Logging);
        report.Should().BeConformant();
        sink.Records.Should().HaveCount(2);
    }

    [Fact]
    public async Task The_in_memory_metrics_collector_should_satisfy_the_metrics_contract()
    {
        var collector = new InMemoryMetricsCollector();

        var report = await SeamContracts.MetricsCollector(collector, Anchor);

        report.Seam.Should().Be(SeamKind.Metrics);
        report.Should().BeConformant();
        collector.Records.Should().HaveCount(2);
    }

    [Fact]
    public void The_sample_attribute_map_should_cover_every_kind()
    {
        SeamContracts.SampleAttributes(Anchor).Values.Select(value => value.Kind)
            .Should().BeEquivalentTo(Enum.GetValues<AttributeValueKind>());
    }

    [Fact]
    public async Task The_contract_suites_should_reject_their_own_arguments()
    {
        var vfsSeam = () => SeamContracts.Vfs(null!, "/root");
        var vfsRoot = () => SeamContracts.Vfs(new InMemoryVfs(), "  ");
        var systemSeam = () => SeamContracts.System(null!, "A", "a", "B");
        var systemPresent = () => SeamContracts.System(new InMemorySystem(), " ", "a", "B");
        var systemValue = () => SeamContracts.System(new InMemorySystem(), "A", null!, "B");
        var systemAbsent = () => SeamContracts.System(new InMemorySystem(), "A", "a", " ");
        var terminalSeam = () => SeamContracts.Terminal(null!, new TerminalCommand("a"), "x", new TerminalCommand("b"), new TerminalCommand("c"));
        var terminalZero = () => SeamContracts.Terminal(new InMemoryTerminal(), null!, "x", new TerminalCommand("b"), new TerminalCommand("c"));
        var terminalStdout = () => SeamContracts.Terminal(new InMemoryTerminal(), new TerminalCommand("a"), null!, new TerminalCommand("b"), new TerminalCommand("c"));
        var terminalNonZero = () => SeamContracts.Terminal(new InMemoryTerminal(), new TerminalCommand("a"), "x", null!, new TerminalCommand("c"));
        var terminalMissing = () => SeamContracts.Terminal(new InMemoryTerminal(), new TerminalCommand("a"), "x", new TerminalCommand("b"), null!);
        var logger = () => SeamContracts.LoggerSink(null!, Anchor);
        var metrics = () => SeamContracts.MetricsCollector(null!, Anchor);
        var report = () => new ContractReport(SeamKind.Vfs, null!);

        await vfsSeam.Should().ThrowAsync<ArgumentNullException>();
        await vfsRoot.Should().ThrowAsync<ArgumentException>();
        await systemSeam.Should().ThrowAsync<ArgumentNullException>();
        await systemPresent.Should().ThrowAsync<ArgumentException>();
        await systemValue.Should().ThrowAsync<ArgumentNullException>();
        await systemAbsent.Should().ThrowAsync<ArgumentException>();
        await terminalSeam.Should().ThrowAsync<ArgumentNullException>();
        await terminalZero.Should().ThrowAsync<ArgumentNullException>();
        await terminalStdout.Should().ThrowAsync<ArgumentNullException>();
        await terminalNonZero.Should().ThrowAsync<ArgumentNullException>();
        await terminalMissing.Should().ThrowAsync<ArgumentNullException>();
        await logger.Should().ThrowAsync<ArgumentNullException>();
        await metrics.Should().ThrowAsync<ArgumentNullException>();
        report.Should().Throw<ArgumentNullException>();
    }
}
