using Microsoft.Extensions.Logging;
using MsLogLevel = Microsoft.Extensions.Logging.LogLevel;
using SeamLogLevel = AtomiCloud.Diene.Interfaces.LogLevel;

namespace AtomiCloud.DotnetBase.UnitTest;

/// <summary>Captures what the sink handed the host logger, without a mocking framework.</summary>
internal sealed class CapturingLogger : ILogger
{
    public List<(MsLogLevel Level, string Message)> Entries { get; } = [];

    /// <summary>The event ids the sink supplied; it does not set one, so these are default.</summary>
    public List<EventId> Events { get; } = [];

    public List<IReadOnlyList<KeyValuePair<string, object?>>> Scopes { get; } = [];

    public bool Throw { get; set; }

    public IDisposable BeginScope<TState>(TState state)
        where TState : notnull
    {
        if (state is IReadOnlyList<KeyValuePair<string, object?>> entries) Scopes.Add(entries);
        return new Scope();
    }

    public bool IsEnabled(MsLogLevel logLevel) => true;

    public void Log<TState>(
        MsLogLevel logLevel,
        EventId eventId,
        TState state,
        Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        if (Throw) throw new InvalidOperationException("logger exploded");
        Events.Add(eventId);
        Entries.Add((logLevel, formatter(state, exception)));
    }

    private sealed class Scope : IDisposable
    {
        public void Dispose()
        {
        }
    }
}

public class OtelLoggerSinkTests
{
    private static Dictionary<string, AttributeValue> Attributes { get; } = new(StringComparer.Ordinal)
    {
        ["route"] = AttributeValue.Text("/v1/demo"),
        ["attempt"] = AttributeValue.Integer(2),
    };

    private static LogRecord Record(
        SeamLogLevel level = SeamLogLevel.Info,
        string? error = null,
        string? stackTrace = null) =>
        new(DateTimeOffset.UnixEpoch, level, "request served", Attributes, error, stackTrace);

    [Theory]
    [InlineData(SeamLogLevel.Trace, MsLogLevel.Trace)]
    [InlineData(SeamLogLevel.Debug, MsLogLevel.Debug)]
    [InlineData(SeamLogLevel.Info, MsLogLevel.Information)]
    [InlineData(SeamLogLevel.Warning, MsLogLevel.Warning)]
    [InlineData(SeamLogLevel.Error, MsLogLevel.Error)]
    [InlineData(SeamLogLevel.Fatal, MsLogLevel.Critical)]
    public void Level_MapsEverySeamSeverity(SeamLogLevel seam, MsLogLevel host) =>
        OtelLoggerSink.Level(seam).Should().Be(host);

    [Fact]
    public void Level_MapsAnUndefinedSeverityToNone() =>
        OtelLoggerSink.Level((SeamLogLevel)42).Should().Be(MsLogLevel.None);

    [Fact]
    public void AttributeKeys_AreTheSemconvExceptionKeys()
    {
        OtelLoggerSink.ErrorKey.Should().Be("exception.message");
        OtelLoggerSink.StackTraceKey.Should().Be("exception.stacktrace");
    }

    [Fact]
    public void State_CarriesEveryAttributeInItsWireForm()
    {
        var state = OtelLoggerSink.State(Record());

        state.Should().HaveCount(2);
        state.Should().Contain(new KeyValuePair<string, object?>("route", "/v1/demo"));
        state.Should().Contain(new KeyValuePair<string, object?>("attempt", "2"));
    }

    [Fact]
    public void State_AddsTheErrorAndStackTraceWhenPresent()
    {
        var state = OtelLoggerSink.State(Record(error: "boom", stackTrace: "at Demo.Run()"));

        state.Should().Contain(new KeyValuePair<string, object?>(OtelLoggerSink.ErrorKey, "boom"));
        state.Should().Contain(new KeyValuePair<string, object?>(OtelLoggerSink.StackTraceKey, "at Demo.Run()"));
    }

    [Fact]
    public void State_OmitsTheErrorAndStackTraceWhenAbsent() =>
        OtelLoggerSink
            .State(Record())
            .Select(entry => entry.Key)
            .Should().NotContain([OtelLoggerSink.ErrorKey, OtelLoggerSink.StackTraceKey]);

    [Fact]
    public void State_RejectsANullRecord() =>
        FluentActions.Invoking(() => OtelLoggerSink.State(null!)).Should().Throw<ArgumentNullException>();

    [Fact]
    public void Construct_RejectsANullLogger() =>
        FluentActions.Invoking(() => new OtelLoggerSink(null!)).Should().Throw<ArgumentNullException>();

    [Fact]
    public void Emit_LogsAtTheMappedLevelWithTheRecordMessage()
    {
        var logger = new CapturingLogger();

        new OtelLoggerSink(logger).Emit(Record(SeamLogLevel.Warning)).Should().BeOk();

        logger.Entries.Should().ContainSingle()
            .Which.Should().Be((MsLogLevel.Warning, "request served"));
        logger.Scopes.Should().ContainSingle().Which.Should().HaveCount(2);
        logger.Events.Should().ContainSingle().Which.Should().Be(default(EventId));
    }

    [Fact]
    public void Emit_RejectsANullRecord() =>
        new OtelLoggerSink(new CapturingLogger())
            .Emit(null!)
            .Should().BeSeamErr(SeamKind.Logging, "invalid_argument");

    [Fact]
    public void Emit_RejectsAnUndefinedSeverity() =>
        new OtelLoggerSink(new CapturingLogger())
            .Emit(new LogRecord(DateTimeOffset.UnixEpoch, (SeamLogLevel)42, "message"))
            .Should().BeSeamErr(SeamKind.Logging, "invalid_wire");

    [Fact]
    public void Emit_ConvertsAThrowingLoggerIntoAnEmitFailure() =>
        new OtelLoggerSink(new CapturingLogger { Throw = true })
            .Emit(Record())
            .Should().BeSeamErr(SeamKind.Logging, "emit_failed")
            .Which.Detail.Should().Contain("logger exploded");

    [Fact]
    public void Emit_IsTotalOverAnEmptyMessageAndNoAttributes() =>
        new OtelLoggerSink(new CapturingLogger())
            .Emit(new LogRecord(DateTimeOffset.UnixEpoch, SeamLogLevel.Info, string.Empty))
            .Should().BeOk();
}
