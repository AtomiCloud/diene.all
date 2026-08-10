using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;
using FluentAssertions.Execution;

namespace AtomiCloud.Diene.Interfaces.TestHelper;

/// <summary>
/// FluentAssertions steps for seam results and recorded emissions. The
/// <c>BeSeamErr</c> step EXTENDS the published
/// <c>AtomiCloud.Diene.Result.TestHelper</c> assertions rather than duplicating
/// them, so a consumer keeps one <c>Should()</c> entry point for Results.
/// </summary>
public static class SeamAssertionExtensions
{
    /// <summary>Asserts the Result failed with a specific seam and failure id.</summary>
    public static AndWhichConstraint<ResultAssertions<T, SeamError>, SeamError> BeSeamErr<T>(
        this ResultAssertions<T, SeamError> assertions,
        SeamKind seam,
        string id,
        string because = "",
        params object[] becauseArgs)
    {
        ArgumentNullException.ThrowIfNull(assertions);
        var error = assertions.BeErr(because, becauseArgs).Which;
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(error.Seam == seam && string.Equals(error.Id, id, StringComparison.Ordinal))
            .FailWith(
                "Expected the result to fail with {0}{reason}, but found {1}.",
                $"{SeamWire.Name(seam)}/{id}",
                $"{SeamWire.Name(error.Seam)}/{error.Id}");
        return new AndWhichConstraint<ResultAssertions<T, SeamError>, SeamError>(assertions, error);
    }

    /// <summary>Starts an assertion chain over a contract report.</summary>
    public static ContractReportAssertions Should(this ContractReport subject) => new(subject);

    /// <summary>Starts an assertion chain over a recording logger sink.</summary>
    public static LoggerSinkAssertions Should(this InMemoryLoggerSink subject) => new(subject);

    /// <summary>Starts an assertion chain over a recording metrics collector.</summary>
    public static MetricsCollectorAssertions Should(this InMemoryMetricsCollector subject) => new(subject);
}

/// <summary>Assertions over a seam contract report.</summary>
/// <param name="subject">The report under assertion.</param>
public sealed class ContractReportAssertions(ContractReport subject)
{
    /// <summary>The report under assertion.</summary>
    public ContractReport Subject { get; } = subject;

    /// <summary>Asserts every case in the suite passed.</summary>
    public AndConstraint<ContractReportAssertions> BeConformant(string because = "", params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.Conformant)
            .FailWith("Expected the seam implementation to be conformant{reason}, but found {0}.", Subject.ToString());
        return new AndConstraint<ContractReportAssertions>(this);
    }
}

/// <summary>Assertions over the records a logger sink captured.</summary>
/// <param name="subject">The sink under assertion.</param>
public sealed class LoggerSinkAssertions(InMemoryLoggerSink subject)
{
    /// <summary>The sink under assertion.</summary>
    public InMemoryLoggerSink Subject { get; } = subject;

    /// <summary>Asserts one record was emitted at a level with an exact message.</summary>
    public AndWhichConstraint<LoggerSinkAssertions, LogRecord> HaveLogged(
        LogLevel level,
        string message,
        string because = "",
        params object[] becauseArgs)
    {
        var match = Subject.Records.FirstOrDefault(record =>
            record.Level == level && string.Equals(record.Message, message, StringComparison.Ordinal));
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(match is not null)
            .FailWith(
                "Expected the logger sink to have logged {0}{reason}, but found {1}.",
                $"{SeamWire.Name(level)} {message}",
                Subject.Records);
        return new AndWhichConstraint<LoggerSinkAssertions, LogRecord>(this, match!);
    }
}

/// <summary>Assertions over the samples a metrics collector captured.</summary>
/// <param name="subject">The collector under assertion.</param>
public sealed class MetricsCollectorAssertions(InMemoryMetricsCollector subject)
{
    /// <summary>The collector under assertion.</summary>
    public InMemoryMetricsCollector Subject { get; } = subject;

    /// <summary>Asserts one sample was emitted with an exact name, kind, and value.</summary>
    public AndWhichConstraint<MetricsCollectorAssertions, MetricRecord> HaveSampled(
        string name,
        MetricKind kind,
        double value,
        string because = "",
        params object[] becauseArgs)
    {
        var match = Subject.Records.FirstOrDefault(record =>
            string.Equals(record.Name, name, StringComparison.Ordinal)
            && record.Kind == kind
            && record.Value.Equals(value));
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(match is not null)
            .FailWith(
                "Expected the metrics collector to have sampled {0}{reason}, but found {1}.",
                $"{SeamWire.Name(kind)} {name}={AttributeValue.Real(value).Wire}",
                Subject.Records);
        return new AndWhichConstraint<MetricsCollectorAssertions, MetricRecord>(this, match!);
    }
}
