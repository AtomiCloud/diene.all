namespace AtomiCloud.Diene.Interfaces.UnitTest;

public class SeamValueTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    [Fact]
    public void It_should_normalize_a_log_record_timestamp_to_utc()
    {
        var record = new LogRecord(new DateTimeOffset(2026, 7, 26, 6, 30, 0, TimeSpan.FromHours(8)), LogLevel.Info, "m");

        record.Timestamp.Should().Be(Anchor);
        record.Timestamp.Offset.Should().Be(TimeSpan.Zero);
    }

    [Fact]
    public void It_should_default_log_optionals_to_none()
    {
        var record = new LogRecord(Anchor, LogLevel.Debug, "message");

        record.Level.Should().Be(LogLevel.Debug);
        record.Message.Should().Be("message");
        record.Attributes.Should().BeEmpty();
        record.Error.IsNone().Should().BeTrue();
        record.StackTrace.IsNone().Should().BeTrue();
    }

    [Fact]
    public void It_should_carry_log_optionals_when_supplied()
    {
        var record = new LogRecord(
            Anchor,
            LogLevel.Error,
            "message",
            [new("key", AttributeValue.Text("value"))],
            "boom",
            "at frame");

        record.Attributes["key"].Should().Be(AttributeValue.Text("value"));
        record.Error.Should().BeSome("boom");
        record.StackTrace.Should().BeSome("at frame");
    }

    [Fact]
    public void It_should_reject_a_null_log_message()
    {
        var act = () => new LogRecord(Anchor, LogLevel.Info, null!);

        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_render_a_log_record_on_the_wire()
    {
        new LogRecord(Anchor, LogLevel.Warning, "careful").ToString()
            .Should().Be("2026-07-25T22:30:00.0000000Z warning careful");
    }

    [Fact]
    public void It_should_normalize_a_metric_timestamp_and_default_its_unit()
    {
        var record = new MetricRecord(
            new DateTimeOffset(2026, 7, 26, 6, 30, 0, TimeSpan.FromHours(8)),
            "app.count",
            MetricKind.Counter,
            1);

        record.Timestamp.Should().Be(Anchor);
        record.Name.Should().Be("app.count");
        record.Kind.Should().Be(MetricKind.Counter);
        record.Value.Should().Be(1);
        record.Unit.IsNone().Should().BeTrue();
        record.Attributes.Should().BeEmpty();
    }

    [Fact]
    public void It_should_carry_metric_optionals_when_supplied()
    {
        var record = new MetricRecord(
            Anchor,
            "app.latency",
            MetricKind.Histogram,
            12.5,
            "ms",
            [new("key", AttributeValue.Text("value"))]);

        record.Unit.Should().BeSome("ms");
        record.Attributes.Should().ContainKey("key");
    }

    [Fact]
    public void It_should_reject_a_blank_metric_name()
    {
        var act = () => new MetricRecord(Anchor, "  ", MetricKind.Gauge, 1);

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_render_a_metric_record_on_the_wire()
    {
        new MetricRecord(Anchor, "app.latency", MetricKind.Histogram, 12.5).ToString()
            .Should().Be("2026-07-25T22:30:00.0000000Z histogram app.latency=12.5");
    }

    [Fact]
    public void It_should_snapshot_a_vfs_entry()
    {
        var entry = new VfsEntry("/tmp/a.txt", VfsEntryType.File, 5, Anchor);

        entry.Path.Should().Be("/tmp/a.txt");
        entry.Type.Should().Be(VfsEntryType.File);
        entry.Size.Should().Be(5);
        entry.ModifiedAt.Should().BeSome(Anchor);
        entry.ToString().Should().Be("file /tmp/a.txt (5)");
    }

    [Fact]
    public void It_should_leave_an_absent_modification_time_as_none()
    {
        new VfsEntry("/tmp", VfsEntryType.Directory, 0).ModifiedAt.IsNone().Should().BeTrue();
    }

    [Fact]
    public void It_should_normalize_an_entry_modification_time_to_utc()
    {
        new VfsEntry("/tmp/a", VfsEntryType.Link, 0, new DateTimeOffset(2026, 7, 26, 6, 30, 0, TimeSpan.FromHours(8)))
            .ModifiedAt.Should().BeSome(Anchor);
    }

    [Fact]
    public void It_should_reject_a_null_entry_path()
    {
        var act = () => new VfsEntry(null!, VfsEntryType.File, 0);

        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_default_every_option_record_to_false()
    {
        default(VfsWriteOptions).CreateParents.Should().BeFalse();
        default(VfsListOptions).Recursive.Should().BeFalse();
        default(VfsDirectoryOptions).Recursive.Should().BeFalse();
        new VfsWriteOptions(true).CreateParents.Should().BeTrue();
        new VfsListOptions(true).Recursive.Should().BeTrue();
        new VfsDirectoryOptions(true).Recursive.Should().BeTrue();
    }

    [Fact]
    public void It_should_snapshot_a_terminal_command()
    {
        var args = new List<string> { "hello" };
        var environment = new Dictionary<string, string>(StringComparer.Ordinal) { ["DIENE"] = "1" };

        var command = new TerminalCommand("echo", args, "/tmp", environment, false, true);
        args.Add("mutated");
        environment["DIENE"] = "2";

        command.Executable.Should().Be("echo");
        command.Args.Should().ContainSingle().Which.Should().Be("hello");
        command.WorkingDirectory.Should().BeSome("/tmp");
        command.Environment["DIENE"].Should().Be("1");
        command.IncludeParentEnvironment.Should().BeFalse();
        command.RunInShell.Should().BeTrue();
        command.ToString().Should().Be("echo hello");
    }

    [Fact]
    public void It_should_default_a_terminal_command_to_an_inherited_environment()
    {
        var command = new TerminalCommand("true");

        command.Args.Should().BeEmpty();
        command.WorkingDirectory.IsNone().Should().BeTrue();
        command.Environment.Should().BeEmpty();
        command.IncludeParentEnvironment.Should().BeTrue();
        command.RunInShell.Should().BeFalse();
        command.ToString().Should().Be("true");
    }

    [Fact]
    public void It_should_reject_a_blank_executable()
    {
        var act = () => new TerminalCommand("  ");

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_treat_only_a_zero_exit_code_as_success()
    {
        new TerminalOutput(0, "out", "err").Succeeded.Should().BeTrue();
        new TerminalOutput(3, "out", "err").Succeeded.Should().BeFalse();

        var output = new TerminalOutput(3, "out", "err");
        output.ExitCode.Should().Be(3);
        output.Stdout.Should().Be("out");
        output.Stderr.Should().Be("err");
    }
}
