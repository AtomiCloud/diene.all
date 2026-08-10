using AtomiCloud.Diene.Interfaces.App.Adapters;

namespace AtomiCloud.Diene.Interfaces.App;

/// <summary>
/// Exercises the full published surface of <c>AtomiCloud.Diene.Interfaces</c> as an
/// in-repo consumer. Each method is a compilable usage example; most results are
/// discarded because the demonstration is the call itself, not its output.
/// </summary>
public static class Samples
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    /// <summary>Runs every demonstration.</summary>
    public static void RunAll()
    {
        Errors();
        Attributes();
        Wire();
        Records();
        Commands();
        Entries();
        Seams().GetAwaiter().GetResult();
    }

    private static void Errors()
    {
        var error = new SeamError(SeamKind.Vfs, "demo", "Demo", "A demonstration failure");
        var enriched = error.With("path", "/tmp/demo");

        _ = error.Seam;
        _ = error.Id;
        _ = error.Title;
        _ = error.Detail;
        _ = error.Data.Count;
        _ = enriched.Equals(error);
        _ = enriched.Equals((object)error);
        _ = enriched.GetHashCode();
        _ = enriched.ToString();
        _ = enriched == error;
        _ = enriched != error;

        _ = SeamErrors.InvalidArgument(SeamKind.System, "name", "blank");
        _ = SeamErrors.NotFound("/tmp/missing");
        _ = SeamErrors.AlreadyExists("/tmp/present");
        _ = SeamErrors.NotADirectory("/tmp/file");
        _ = SeamErrors.DirectoryNotEmpty("/tmp/dir");
        _ = SeamErrors.IoFailure(SeamKind.Vfs, "read", "disk on fire");
        _ = SeamErrors.EnvironmentUnavailable("HOME", "denied");
        _ = SeamErrors.LaunchFailed("nope", "not found");
        _ = SeamErrors.EmitFailed(SeamKind.Metrics, "closed");
        _ = SeamErrors.Cancelled(SeamKind.Terminal, "run");
        _ = SeamErrors.InvalidWire("instant", "not-a-date");
        _ = SeamErrors.UnknownTimeZone("Mars/Olympus", "unknown");
    }

    private static void Attributes()
    {
        var text = AttributeValue.Text("value");
        var integer = AttributeValue.Integer(42);
        var real = AttributeValue.Real(1.5);
        var flag = AttributeValue.Flag(true);
        var instant = AttributeValue.Instant(Anchor);
        var duration = AttributeValue.Duration(TimeSpan.FromMinutes(3));
        var zone = AttributeValue.TimeZone(TimeZoneInfo.Utc.Id);

        _ = text.Kind;
        _ = text.Wire;
        _ = text.AsText();
        _ = integer.AsInteger();
        _ = real.AsReal();
        _ = flag.AsFlag();
        _ = instant.AsInstant();
        _ = duration.AsDuration();
        _ = zone.Then(value => value.AsTimeZone().Map(_ => value));
        _ = text.Equals(integer);
        _ = text.Equals((object)integer);
        _ = text.GetHashCode();
        _ = text.ToString();
        _ = text == integer;
        _ = text != integer;

        _ = AttributeValue.FromWire(AttributeValueKind.Text, "value");
        _ = AttributeValue.FromWire(AttributeValueKind.Integer, "42");
        _ = AttributeValue.FromWire(AttributeValueKind.Real, "1.5");
        _ = AttributeValue.FromWire(AttributeValueKind.Flag, "true");
        _ = AttributeValue.FromWire(AttributeValueKind.Instant, SeamWire.Instant(Anchor));
        _ = AttributeValue.FromWire(AttributeValueKind.Duration, "PT3M");
        _ = AttributeValue.FromWire(AttributeValueKind.TimeZone, TimeZoneInfo.Utc.Id);

        _ = SeamAttributes.Empty.Count;
        _ = SeamAttributes.Copy([new("text", text)]).Count;
    }

    private static void Wire()
    {
        _ = SeamWire.InstantFormat;
        _ = SeamWire.Instant(Anchor);
        _ = SeamWire.ParseInstant(SeamWire.Instant(Anchor));
        _ = SeamWire.Duration(TimeSpan.FromSeconds(90));
        _ = SeamWire.ParseDuration("PT1M30S");
        _ = SeamWire.TimeZone(TimeZoneInfo.Utc.Id);

        _ = SeamWire.Name(SeamKind.Logging);
        _ = SeamWire.Name(LogLevel.Warning);
        _ = SeamWire.Name(MetricKind.Gauge);
        _ = SeamWire.Name(VfsEntryType.Link);
        _ = SeamWire.Name(AttributeValueKind.Duration);

        _ = SeamWire.ParseSeamKind("logging");
        _ = SeamWire.ParseLogLevel("warning");
        _ = SeamWire.ParseMetricKind("gauge");
        _ = SeamWire.ParseVfsEntryType("link");
        _ = SeamWire.ParseAttributeValueKind("duration");
    }

    private static void Records()
    {
        var log = new LogRecord(
            Anchor,
            LogLevel.Error,
            "demo",
            [new("text", AttributeValue.Text("value"))],
            "boom",
            "at demo");

        _ = log.Timestamp;
        _ = log.Level;
        _ = log.Message;
        _ = log.Attributes.Count;
        _ = log.Error;
        _ = log.StackTrace;
        _ = log.ToString();
        _ = new LogRecord(Anchor, LogLevel.Trace, "trace");
        _ = new LogRecord(Anchor, LogLevel.Debug, "debug");
        _ = new LogRecord(Anchor, LogLevel.Info, "info");
        _ = new LogRecord(Anchor, LogLevel.Fatal, "fatal");

        var metric = new MetricRecord(
            Anchor,
            "demo.latency",
            MetricKind.Histogram,
            12.5,
            "ms",
            [new("text", AttributeValue.Text("value"))]);

        _ = metric.Timestamp;
        _ = metric.Name;
        _ = metric.Kind;
        _ = metric.Value;
        _ = metric.Unit;
        _ = metric.Attributes.Count;
        _ = metric.ToString();
        _ = new MetricRecord(Anchor, "demo.count", MetricKind.Counter, 1);
        _ = new MetricRecord(Anchor, "demo.level", MetricKind.Gauge, 2);
    }

    private static void Commands()
    {
        var command = new TerminalCommand(
            "echo",
            ["hello"],
            "/tmp",
            [new("DIENE", "1")],
            includeParentEnvironment: false,
            runInShell: true);

        _ = command.Executable;
        _ = command.Args.Count;
        _ = command.WorkingDirectory;
        _ = command.Environment.Count;
        _ = command.IncludeParentEnvironment;
        _ = command.RunInShell;
        _ = command.ToString();

        var output = new TerminalOutput(0, "hello", string.Empty);
        _ = output.ExitCode;
        _ = output.Stdout;
        _ = output.Stderr;
        _ = output.Succeeded;
    }

    private static void Entries()
    {
        var entry = new VfsEntry("/tmp/demo.txt", VfsEntryType.File, 5, Anchor);
        _ = entry.Path;
        _ = entry.Type;
        _ = entry.Size;
        _ = entry.ModifiedAt;
        _ = entry.ToString();
        _ = new VfsEntry("/tmp", VfsEntryType.Directory, 0);

        _ = new VfsWriteOptions(true).CreateParents;
        _ = new VfsListOptions(true).Recursive;
        _ = new VfsDirectoryOptions(true).Recursive;
    }

    private static async Task Seams()
    {
        ISystem system = new HostSystem();
        IVfs vfs = new HostVfs();
        ITerminal terminal = new HostTerminal();
        ILoggerSink logger = new TextWriterLoggerSink(TextWriter.Null);
        IMetricsCollector metrics = new TextWriterMetricsCollector(TextWriter.Null);

        _ = system.Environment("HOME");
        _ = system.CurrentDirectory();
        _ = system.NowUtc();
        _ = await system.Delay(TimeSpan.Zero).ConfigureAwait(false);

        var scratch = Path.Combine(Path.GetTempPath(), $"diene-interfaces-demo-{Guid.NewGuid():N}");
        var file = Path.Combine(scratch, "demo.txt");
        _ = await vfs.CreateDirectory(scratch, new VfsDirectoryOptions(true)).ConfigureAwait(false);
        _ = await vfs.WriteText(file, "hello").ConfigureAwait(false);
        _ = await vfs.WriteBytes(file, new ReadOnlyMemory<byte>([1, 2, 3])).ConfigureAwait(false);
        _ = await vfs.Exists(file).ConfigureAwait(false);
        _ = await vfs.ReadText(file).ConfigureAwait(false);
        _ = await vfs.ReadBytes(file).ConfigureAwait(false);
        _ = await vfs.List(scratch).ConfigureAwait(false);
        _ = await vfs.Delete(scratch, new VfsDirectoryOptions(true)).ConfigureAwait(false);

        _ = await terminal.Run(new TerminalCommand("true")).ConfigureAwait(false);
        _ = logger.Emit(new LogRecord(Anchor, LogLevel.Info, "demo"));
        _ = metrics.Emit(new MetricRecord(Anchor, "demo.count", MetricKind.Counter, 1));
    }
}
