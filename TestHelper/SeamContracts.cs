using System.Collections.Immutable;
using System.Text;

namespace AtomiCloud.Diene.Interfaces.TestHelper;

/// <summary>
/// The shared behavioural suite for each seam this library declares. ONE suite per
/// interface runs against BOTH a real implementation and a fake, which is the
/// contract-parity tier for an interfaces library: a mock that passes here behaves
/// like a host-backed adapter, and an adapter that passes here is substitutable by
/// the mock.
/// </summary>
public static class SeamContracts
{
    /// <summary>A sample attribute map exercising every <see cref="AttributeValueKind"/>.</summary>
    public static IReadOnlyDictionary<string, AttributeValue> SampleAttributes(DateTimeOffset instant) =>
        ImmutableSortedDictionary.CreateRange(
            StringComparer.Ordinal,
            new KeyValuePair<string, AttributeValue>[]
            {
                new("text", AttributeValue.Text("value")),
                new("integer", AttributeValue.Integer(42)),
                new("real", AttributeValue.Real(1.5)),
                new("flag", AttributeValue.Flag(true)),
                new("instant", AttributeValue.Instant(instant)),
                new("duration", AttributeValue.Duration(TimeSpan.FromSeconds(90))),
                new("timeZone", AttributeValue.TimeZone(TimeZoneInfo.Utc.Id).GetOr(AttributeValue.Text("unresolved"))),
            });

    /// <summary>Runs the virtual filesystem contract inside a scratch directory below <paramref name="root"/>.</summary>
    public static async Task<ContractReport> Vfs(IVfs vfs, string root)
    {
        ArgumentNullException.ThrowIfNull(vfs);
        ArgumentException.ThrowIfNullOrWhiteSpace(root);

        var scope = Join(root, "diene-interfaces-contract");
        var file = Join(scope, "file.txt");
        var missing = Join(scope, "missing.txt");
        var absentDirectory = Join(scope, "absent");
        var absentChild = Join(absentDirectory, "child.txt");
        var deep = Join(scope, "deep");
        var nested = Join(deep, "nested.txt");
        var payload = Encoding.UTF8.GetBytes("bytes");

        List<ContractCase> cases =
        [
            await Case(
                "create_directory_recursive_creates_scope",
                async () => Ok(await vfs.CreateDirectory(scope, new VfsDirectoryOptions(true)))),
            await Case(
                "create_directory_recursive_is_idempotent",
                async () => Ok(await vfs.CreateDirectory(scope, new VfsDirectoryOptions(true)))),
            await Case(
                "create_directory_non_recursive_rejects_existing",
                async () => Err(await vfs.CreateDirectory(scope), "already_exists")),
            await Case("exists_is_false_for_missing", async () => OkValue(await vfs.Exists(missing), false)),
            await Case("read_text_missing_is_not_found", async () => Err(await vfs.ReadText(missing), "not_found")),
            await Case("write_text_succeeds", async () => Ok(await vfs.WriteText(file, "hello"))),
            await Case("read_text_round_trips", async () => OkValue(await vfs.ReadText(file), "hello")),
            await Case("exists_is_true_after_write", async () => OkValue(await vfs.Exists(file), true)),
            await Case(
                "write_bytes_then_read_bytes_round_trips",
                async () => Ok(await vfs.WriteBytes(file, payload))
                    ?? OkWith(await vfs.ReadBytes(file), read => read.Span.SequenceEqual(payload))),
            await Case(
                "write_without_create_parents_is_not_found",
                async () => Err(await vfs.WriteText(absentChild, "no"), "not_found")),
            await Case(
                "write_with_create_parents_creates_ancestors",
                async () => Ok(await vfs.WriteText(nested, "deep", new VfsWriteOptions(true)))
                    ?? OkValue(await vfs.Exists(nested), true)),
            await Case(
                "list_returns_direct_children_only",
                async () => OkWith(
                    await vfs.List(scope),
                    entries => entries.Any(entry => Same(entry.Path, file))
                        && entries.Any(entry => Same(entry.Path, deep) && entry.Type == VfsEntryType.Directory)
                        && !entries.Any(entry => Same(entry.Path, nested)))),
            await Case(
                "list_recursive_includes_descendants",
                async () => OkWith(
                    await vfs.List(scope, new VfsListOptions(true)),
                    entries => entries.Any(entry => Same(entry.Path, nested)))),
            await Case(
                "list_reports_file_type_and_size",
                async () => OkWith(
                    await vfs.List(scope),
                    entries => entries.Any(entry =>
                        Same(entry.Path, file) && entry.Type == VfsEntryType.File && entry.Size == payload.Length))),
            await Case("list_on_file_is_not_a_directory", async () => Err(await vfs.List(file), "not_a_directory")),
            await Case("list_on_missing_is_not_found", async () => Err(await vfs.List(absentDirectory), "not_found")),
            await Case("delete_missing_is_not_found", async () => Err(await vfs.Delete(missing), "not_found")),
            await Case(
                "delete_non_empty_directory_needs_recursive",
                async () => Err(await vfs.Delete(deep), "directory_not_empty")),
            await Case(
                "delete_recursive_removes_the_tree",
                async () => Ok(await vfs.Delete(deep, new VfsDirectoryOptions(true)))
                    ?? OkValue(await vfs.Exists(nested), false)),
            await Case(
                "delete_removes_a_file",
                async () => Ok(await vfs.Delete(file)) ?? OkValue(await vfs.Exists(file), false)),
            await Case(
                "delete_recursive_removes_the_scope",
                async () => Ok(await vfs.Delete(scope, new VfsDirectoryOptions(true)))),
        ];

        return new ContractReport(SeamKind.Vfs, cases);
    }

    /// <summary>Runs the system contract against a variable that is set and one that is not.</summary>
    public static async Task<ContractReport> System(
        ISystem system,
        string presentVariable,
        string presentValue,
        string absentVariable)
    {
        ArgumentNullException.ThrowIfNull(system);
        ArgumentException.ThrowIfNullOrWhiteSpace(presentVariable);
        ArgumentNullException.ThrowIfNull(presentValue);
        ArgumentException.ThrowIfNullOrWhiteSpace(absentVariable);

        using var cancelled = new CancellationTokenSource();
        await cancelled.CancelAsync().ConfigureAwait(false);

        List<ContractCase> cases =
        [
            await Case(
                "environment_present_is_some",
                () => OkWith(
                    system.Environment(presentVariable),
                    value => value.Match(
                        actual => string.Equals(actual, presentValue, StringComparison.Ordinal),
                        () => false))),
            await Case(
                "environment_absent_is_none",
                () => OkWith(system.Environment(absentVariable), value => value.IsNone())),
            await Case(
                "environment_blank_name_is_invalid_argument",
                () => Err(system.Environment("  "), "invalid_argument")),
            await Case(
                "current_directory_is_not_blank",
                () => OkWith(system.CurrentDirectory(), value => !string.IsNullOrWhiteSpace(value))),
            await Case("now_utc_has_zero_offset", () => OkWith(system.NowUtc(), now => now.Offset == TimeSpan.Zero)),
            await Case(
                "now_utc_never_moves_backwards",
                () => OkWith(
                    system.NowUtc().Then(first => system.NowUtc().Map(second => second >= first)),
                    holds => holds)),
            await Case("delay_zero_completes", async () => Ok(await system.Delay(TimeSpan.Zero))),
            await Case(
                "delay_cancelled_is_cancelled",
                async () => Err(await system.Delay(TimeSpan.FromSeconds(30), cancelled.Token), "cancelled")),
        ];

        return new ContractReport(SeamKind.System, cases);
    }

    /// <summary>Runs the terminal contract against three caller-declared invocations.</summary>
    /// <param name="terminal">The seam under test.</param>
    /// <param name="zeroExit">A command that must exit zero.</param>
    /// <param name="expectedStdout">A fragment the zero-exit command must print.</param>
    /// <param name="nonZeroExit">A command that must exit non-zero WITHOUT failing the seam.</param>
    /// <param name="unlaunchable">A command whose program cannot be launched.</param>
    public static async Task<ContractReport> Terminal(
        ITerminal terminal,
        TerminalCommand zeroExit,
        string expectedStdout,
        TerminalCommand nonZeroExit,
        TerminalCommand unlaunchable)
    {
        ArgumentNullException.ThrowIfNull(terminal);
        ArgumentNullException.ThrowIfNull(zeroExit);
        ArgumentNullException.ThrowIfNull(expectedStdout);
        ArgumentNullException.ThrowIfNull(nonZeroExit);
        ArgumentNullException.ThrowIfNull(unlaunchable);

        List<ContractCase> cases =
        [
            await Case(
                "zero_exit_is_a_successful_output",
                async () => OkWith(
                    await terminal.Run(zeroExit),
                    output => output.Succeeded
                        && output.ExitCode == 0
                        && output.Stdout.Contains(expectedStdout, StringComparison.Ordinal))),
            await Case(
                "non_zero_exit_is_still_a_successful_output",
                async () => OkWith(
                    await terminal.Run(nonZeroExit),
                    output => !output.Succeeded && output.ExitCode != 0)),
            await Case(
                "unlaunchable_program_is_launch_failed",
                async () => Err(await terminal.Run(unlaunchable), "launch_failed")),
        ];

        return new ContractReport(SeamKind.Terminal, cases);
    }

    /// <summary>Runs the logger sink contract.</summary>
    public static async Task<ContractReport> LoggerSink(ILoggerSink sink, DateTimeOffset instant)
    {
        ArgumentNullException.ThrowIfNull(sink);

        List<ContractCase> cases =
        [
            await Case(
                "accepts_a_minimal_record",
                () => Ok(sink.Emit(new LogRecord(instant, LogLevel.Info, "contract")))),
            await Case(
                "accepts_every_attribute_kind",
                () => Ok(sink.Emit(new LogRecord(
                    instant,
                    LogLevel.Error,
                    "contract",
                    SampleAttributes(instant),
                    "boom",
                    "at contract")))),
        ];

        return new ContractReport(SeamKind.Logging, cases);
    }

    /// <summary>Runs the metrics collector contract.</summary>
    public static async Task<ContractReport> MetricsCollector(IMetricsCollector collector, DateTimeOffset instant)
    {
        ArgumentNullException.ThrowIfNull(collector);

        List<ContractCase> cases =
        [
            await Case(
                "accepts_a_counter_sample",
                () => Ok(collector.Emit(new MetricRecord(instant, "contract.count", MetricKind.Counter, 1)))),
            await Case(
                "accepts_every_attribute_kind",
                () => Ok(collector.Emit(new MetricRecord(
                    instant,
                    "contract.latency",
                    MetricKind.Histogram,
                    12.5,
                    "ms",
                    SampleAttributes(instant))))),
        ];

        return new ContractReport(SeamKind.Metrics, cases);
    }

    private static string Join(string parent, string child) => $"{parent.TrimEnd('/')}/{child}";

    private static bool Same(string left, string right) =>
        string.Equals(VfsPath.Normalize(left), VfsPath.Normalize(right), StringComparison.Ordinal);

    private static string? Ok<T>(Result<T, SeamError> result) =>
        result.Match<string?>(_ => null, error => $"expected success, got {error}");

    private static string? OkValue<T>(Result<T, SeamError> result, T expected) =>
        result.Match<string?>(
            value => EqualityComparer<T>.Default.Equals(value, expected) ? null : $"expected {expected}, got {value}",
            error => $"expected {expected}, got {error}");

    private static string? OkWith<T>(Result<T, SeamError> result, Func<T, bool> predicate) =>
        result.Match<string?>(value => predicate(value) ? null : $"value {value} failed the contract predicate", error => $"expected success, got {error}");

    private static string? Err<T>(Result<T, SeamError> result, string expectedId) =>
        result.Match<string?>(
            value => $"expected the {expectedId} failure, got success {value}",
            error => string.Equals(error.Id, expectedId, StringComparison.Ordinal) ? null : $"expected the {expectedId} failure, got {error}");

    private static Task<ContractCase> Case(string name, Func<string?> check) =>
        Case(name, () => Task.FromResult(check()));

    private static async Task<ContractCase> Case(string name, Func<Task<string?>> check)
    {
        try
        {
            return new ContractCase(name, Option.FromNullable(await check().ConfigureAwait(false)));
        }
#pragma warning disable CA1031 // An implementation that THROWS violates the seam contract; reporting it as a failed case is the point.
        catch (Exception exception)
        {
            return new ContractCase(name, Option.Some($"threw {exception.GetType().Name}: {exception.Message}"));
        }
#pragma warning restore CA1031
    }
}
