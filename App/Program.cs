using System.Globalization;
using AtomiCloud.Diene.Interfaces.App.Adapters;

namespace AtomiCloud.Diene.Interfaces.App;

/// <summary>
/// Composition root: explicit wiring of the shared seams to host-backed adapters.
/// A real service swaps these adapters for its own without changing a single
/// consumer, which is the whole point of the seam library.
/// </summary>
public static class Program
{
    /// <summary>Runs the demonstration and prints one railway-composed line.</summary>
    public static async Task Main()
    {
        Samples.RunAll();

        // ── Seam wiring (illustrative) — a service substitutes its own adapters here ──
        ISystem system = new HostSystem();
        IVfs vfs = new HostVfs();
        ILoggerSink logger = new TextWriterLoggerSink(Console.Out);
        IMetricsCollector metrics = new TextWriterMetricsCollector(TextWriter.Null);

        var scratch = Path.Combine(Path.GetTempPath(), $"diene-interfaces-app-{Guid.NewGuid():N}");
        var file = Path.Combine(scratch, "answer.txt");

        var message = await Doubled(system, vfs, logger, metrics, scratch, file).ConfigureAwait(false);
        _ = await vfs.Delete(scratch, new VfsDirectoryOptions(true)).ConfigureAwait(false);
        Console.WriteLine(message);
        // ── End seam wiring ──
    }

    private static async Task<string> Doubled(
        ISystem system,
        IVfs vfs,
        ILoggerSink logger,
        IMetricsCollector metrics,
        string scratch,
        string file)
    {
        var now = system.NowUtc();
        if (now.IsFailure(out var clockError)) return Failure(clockError);

        var created = await vfs.CreateDirectory(scratch, new VfsDirectoryOptions(true)).ConfigureAwait(false);
        if (created.IsFailure(out var createError)) return Failure(createError);

        var written = await vfs.WriteText(file, "21").ConfigureAwait(false);
        if (written.IsFailure(out var writeError)) return Failure(writeError);

        var read = await vfs.ReadText(file).ConfigureAwait(false);
        return read
            .Then(Parse)
            .Do(value => logger.Emit(new LogRecord(
                now.Get(),
                LogLevel.Info,
                "doubled the stored answer",
                [new("source", AttributeValue.Text(file))])))
            .Do(value => metrics.Emit(new MetricRecord(now.Get(), "app.answer", MetricKind.Gauge, value * 2)))
            .Match(value => $"Success: {value * 2}", Failure);
    }

    private static string Failure(SeamError error) => $"Failure: {error}";

    private static Result<int, SeamError> Parse(string text) =>
        int.TryParse(text, CultureInfo.InvariantCulture, out var value)
            ? Result.Ok<int, SeamError>(value)
            : SeamErrors.InvalidWire("integer", text);
}
