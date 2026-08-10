namespace AtomiCloud.Diene.Interfaces.UnitTest.Meta;

/// <summary>
/// META tier — the fixture/builder invariants of the shipped mocks: settable state,
/// injectable faults, argument guards, and independently owned snapshots.
/// </summary>
public class InMemorySeamTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    private static CancellationToken Token => TestContext.Current.CancellationToken;

    [Fact]
    public void The_system_mock_should_expose_a_settable_environment()
    {
        var system = new InMemorySystem(Anchor, "/work", [new("KEEP", "1")]);

        system.SetEnvironment("ADDED", "2");
        system.Environment("KEEP").Should().BeOk().Which.Should().BeSome("1");
        system.Environment("ADDED").Should().BeOk().Which.Should().BeSome("2");

        system.RemoveEnvironment("ADDED");
        system.Environment("ADDED").Should().BeOk().Which.IsNone().Should().BeTrue();
    }

    [Fact]
    public void The_system_mock_should_expose_a_settable_clock()
    {
        var system = new InMemorySystem(Anchor);

        system.NowUtc().Should().BeOk(Anchor);

        system.Advance(TimeSpan.FromMinutes(1));
        system.NowUtc().Should().BeOk(Anchor.AddMinutes(1));

        system.SetNow(Anchor);
        system.NowUtc().Should().BeOk(Anchor);
    }

    [Fact]
    public void The_system_mock_should_default_its_clock_and_directory()
    {
        var system = new InMemorySystem();

        system.NowUtc().Should().BeOk(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));
        system.CurrentDirectory().Should().BeOk("/work");
    }

    [Fact]
    public void The_system_mock_should_normalize_a_supplied_clock_to_utc()
    {
        new InMemorySystem(new DateTimeOffset(2026, 7, 26, 6, 30, 0, TimeSpan.FromHours(8)))
            .NowUtc().Should().BeOk(Anchor);
    }

    [Fact]
    public void The_system_mock_should_expose_a_settable_directory()
    {
        var system = new InMemorySystem(Anchor);

        system.SetDirectory("/other");

        system.CurrentDirectory().Should().BeOk("/other");
    }

    [Fact]
    public async Task The_system_mock_should_record_and_apply_delays()
    {
        var system = new InMemorySystem(Anchor);

        (await system.Delay(TimeSpan.FromSeconds(5), Token)).Should().BeOk();

        system.RequestedDelays.Should().Equal(TimeSpan.FromSeconds(5));
        system.NowUtc().Should().BeOk(Anchor.AddSeconds(5));
    }

    [Fact]
    public async Task The_system_mock_should_report_a_cancelled_delay_as_a_failure_value()
    {
        using var cancelled = new CancellationTokenSource();
        await cancelled.CancelAsync();

        (await new InMemorySystem(Anchor).Delay(TimeSpan.FromSeconds(5), cancelled.Token))
            .Should().BeSeamErr(SeamKind.System, "cancelled");
    }

    [Fact]
    public async Task The_system_mock_should_inject_one_queued_failure_per_call()
    {
        var system = new InMemorySystem(Anchor);
        var failure = SeamErrors.IoFailure(SeamKind.System, "probe", "injected");

        system.EnqueueFailure(failure);
        system.Environment("ANY").Should().BeSeamErr(SeamKind.System, "io_failure");
        system.Environment("ANY").Should().BeOk();

        system.EnqueueFailure(failure);
        system.CurrentDirectory().Should().BeSeamErr(SeamKind.System, "io_failure");

        system.EnqueueFailure(failure);
        system.NowUtc().Should().BeSeamErr(SeamKind.System, "io_failure");

        system.EnqueueFailure(failure);
        (await system.Delay(TimeSpan.Zero, Token)).Should().BeSeamErr(SeamKind.System, "io_failure");
    }

    [Fact]
    public void The_system_mock_should_reject_a_blank_variable_name()
    {
        new InMemorySystem(Anchor).Environment("  ").Should().BeSeamErr(SeamKind.System, "invalid_argument");
    }

    [Fact]
    public void The_system_mock_should_guard_its_builders()
    {
        var system = new InMemorySystem(Anchor);
        var directory = () => new InMemorySystem(Anchor, "  ");
        var setName = () => system.SetEnvironment(" ", "v");
        var setValue = () => system.SetEnvironment("k", null!);
        var remove = () => system.RemoveEnvironment(" ");
        var setDirectory = () => system.SetDirectory(" ");
        var failure = () => system.EnqueueFailure(null!);

        directory.Should().Throw<ArgumentException>();
        setName.Should().Throw<ArgumentException>();
        setValue.Should().Throw<ArgumentNullException>();
        remove.Should().Throw<ArgumentException>();
        setDirectory.Should().Throw<ArgumentException>();
        failure.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task The_vfs_mock_should_seed_files_with_their_ancestors()
    {
        var vfs = new InMemoryVfs(Anchor);

        vfs.Seed("/a/b/c.txt", "hello");

        (await vfs.ReadText("/a/b/c.txt", Token)).Should().BeOk("hello");
        vfs.Directories.Should().Contain(["/", "/a", "/a/b"]);
        vfs.Files.Should().ContainKey("/a/b/c.txt");
    }

    [Fact]
    public async Task The_vfs_mock_should_report_entry_metadata_from_its_fixed_clock()
    {
        var vfs = new InMemoryVfs(Anchor);
        vfs.Seed("/a/b.txt", "hello");

        var entries = (await vfs.List("/a", default, Token)).Should().BeOk().Which;

        entries.Should().ContainSingle().Which.ModifiedAt.Should().BeSome(Anchor);
    }

    [Fact]
    public async Task The_vfs_mock_should_inject_one_queued_failure_per_call()
    {
        var vfs = new InMemoryVfs(Anchor);

        vfs.EnqueueFailure(SeamErrors.IoFailure(SeamKind.Vfs, "probe", "injected"));

        (await vfs.Exists("/a", Token)).Should().BeSeamErr(SeamKind.Vfs, "io_failure");
        (await vfs.Exists("/a", Token)).Should().BeOk(false);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_vfs_mock_should_reject_a_blank_path(string path)
    {
        var vfs = new InMemoryVfs(Anchor);
        var token = Token;

        (await vfs.Exists(path, token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.ReadBytes(path, token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.ReadText(path, token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.WriteBytes(path, ReadOnlyMemory<byte>.Empty, default, token))
            .Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.WriteText(path, "x", default, token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.List(path, default, token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.CreateDirectory(path, default, token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
        (await vfs.Delete(path, default, token)).Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Fact]
    public async Task The_vfs_mock_should_refuse_a_non_recursive_directory_under_a_missing_parent()
    {
        (await new InMemoryVfs(Anchor).CreateDirectory("/a/b", default, Token))
            .Should().BeSeamErr(SeamKind.Vfs, "not_found");
    }

    [Fact]
    public async Task The_vfs_mock_should_treat_an_existing_file_as_an_occupied_directory_path()
    {
        var vfs = new InMemoryVfs(Anchor);
        vfs.Seed("/a.txt", "hello");

        (await vfs.CreateDirectory("/a.txt", default, Token)).Should().BeSeamErr(SeamKind.Vfs, "already_exists");
        (await vfs.CreateDirectory("/a.txt", new VfsDirectoryOptions(true), Token)).Should().BeOk();
    }

    [Fact]
    public async Task The_vfs_mock_should_expose_independently_owned_snapshots()
    {
        var vfs = new InMemoryVfs(Anchor);
        vfs.Seed("/a.txt", "hello");

        var before = vfs.Files;
        var directories = vfs.Directories;
        (await vfs.WriteText("/b.txt", "world", default, Token)).Should().BeOk();

        before.Should().HaveCount(1);
        directories.Should().HaveCount(1);
        vfs.Files.Should().HaveCount(2);
    }

    [Fact]
    public async Task The_vfs_mock_should_guard_its_builders()
    {
        var vfs = new InMemoryVfs(Anchor);
        var path = () => vfs.Seed(" ", "x");
        var content = () => vfs.Seed("/a", null!);
        var failure = () => vfs.EnqueueFailure(null!);
        var writeContent = async () => await vfs.WriteText("/a", null!, default, Token);

        path.Should().Throw<ArgumentException>();
        content.Should().Throw<ArgumentNullException>();
        failure.Should().Throw<ArgumentNullException>();
        await writeContent.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task The_terminal_mock_should_record_commands_and_script_outputs()
    {
        var terminal = new InMemoryTerminal();
        var token = Token;
        terminal.Program("ok", new TerminalOutput(0, "hello", string.Empty));
        terminal.Fail("bad", SeamErrors.LaunchFailed("bad", "scripted"));

        (await terminal.Run(new TerminalCommand("ok", ["arg"]), token)).Should().BeOk()
            .Which.Stdout.Should().Be("hello");
        (await terminal.Run(new TerminalCommand("bad"), token))
            .Should().BeSeamErr(SeamKind.Terminal, "launch_failed");
        (await terminal.Run(new TerminalCommand("absent"), token))
            .Should().BeSeamErr(SeamKind.Terminal, "launch_failed");

        terminal.Commands.Select(command => command.Executable).Should().Equal("ok", "bad", "absent");
    }

    [Fact]
    public async Task The_terminal_mock_should_reject_a_null_command()
    {
        (await new InMemoryTerminal().Run(null!, Token))
            .Should().BeSeamErr(SeamKind.Terminal, "invalid_argument");
    }

    [Fact]
    public void The_terminal_mock_should_guard_its_builders()
    {
        var terminal = new InMemoryTerminal();
        var program = () => terminal.Program(" ", default);
        var failExecutable = () => terminal.Fail(" ", SeamErrors.LaunchFailed("x", "y"));
        var failError = () => terminal.Fail("x", null!);

        program.Should().Throw<ArgumentException>();
        failExecutable.Should().Throw<ArgumentException>();
        failError.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void The_sink_mocks_should_record_inject_and_guard()
    {
        var logger = new InMemoryLoggerSink();
        var collector = new InMemoryMetricsCollector();

        logger.EnqueueFailure(SeamErrors.EmitFailed(SeamKind.Logging, "injected"));
        logger.Emit(new LogRecord(Anchor, LogLevel.Info, "one")).Should().BeSeamErr(SeamKind.Logging, "emit_failed");
        logger.Emit(new LogRecord(Anchor, LogLevel.Info, "one")).Should().BeOk();
        logger.Emit(null!).Should().BeSeamErr(SeamKind.Logging, "invalid_argument");
        logger.Records.Should().ContainSingle();

        collector.EnqueueFailure(SeamErrors.EmitFailed(SeamKind.Metrics, "injected"));
        collector.Emit(new MetricRecord(Anchor, "m", MetricKind.Gauge, 1))
            .Should().BeSeamErr(SeamKind.Metrics, "emit_failed");
        collector.Emit(new MetricRecord(Anchor, "m", MetricKind.Gauge, 1)).Should().BeOk();
        collector.Emit(null!).Should().BeSeamErr(SeamKind.Metrics, "invalid_argument");
        collector.Records.Should().ContainSingle();

        var loggerFailure = () => logger.EnqueueFailure(null!);
        var collectorFailure = () => collector.EnqueueFailure(null!);
        loggerFailure.Should().Throw<ArgumentNullException>();
        collectorFailure.Should().Throw<ArgumentNullException>();
    }
}
