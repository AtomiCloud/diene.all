using System.ComponentModel;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace AtomiCloud.Diene.Problems.UnitTest;

[Description("A sample problem used by library contract tests.")]
internal sealed class SampleProblem : IDomainProblem
{
    public SampleProblem()
    {
    }

    public SampleProblem(string value, string detail = "sample detail")
    {
        Value = value;
        Detail = detail;
    }

    [JsonIgnore]
    public string Id => "sample_problem";

    [JsonIgnore]
    public string Title => "Sample Problem";

    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    [JsonIgnore]
    public string Version => "v1";

    [Description("The sample payload value.")]
    public string Value { get; } = string.Empty;
}

internal sealed class OtherProblem : IDomainProblem
{
    [JsonIgnore]
    public string Id => "other_problem";

    [JsonIgnore]
    public string Title => "Other Problem";

    [JsonIgnore]
    public string Detail => "other detail";

    [JsonIgnore]
    public string Version => "v1";

    public int Code => 7;
}

internal sealed class SpoofedSampleProblem : IDomainProblem
{
    [JsonIgnore]
    public string Id => "sample_problem";

    [JsonIgnore]
    public string Title => "Spoofed Sample";

    [JsonIgnore]
    public string Detail => "spoofed";

    [JsonIgnore]
    public string Version => "v1";
}

internal sealed class VersionTwoProblem : IDomainProblem
{
    [JsonIgnore]
    public string Id => "version_two";

    [JsonIgnore]
    public string Title => "Version Two";

    [JsonIgnore]
    public string Detail => "v2";

    [JsonIgnore]
    public string Version => "v2";
}

internal sealed class BadIdProblem : IDomainProblem
{
    [JsonIgnore]
    public string Id => "bad-id";

    [JsonIgnore]
    public string Title => "Bad Id";

    [JsonIgnore]
    public string Detail => "bad";

    [JsonIgnore]
    public string Version => "v1";
}

internal sealed class BadVersionProblem : IDomainProblem
{
    [JsonIgnore]
    public string Id => "bad_version";

    [JsonIgnore]
    public string Title => "Bad Version";

    [JsonIgnore]
    public string Detail => "bad";

    [JsonIgnore]
    public string Version => "V1";
}

internal sealed class BlankTitleProblem : IDomainProblem
{
    [JsonIgnore]
    public string Id => "blank_title";

    [JsonIgnore]
    public string Title => " ";

    [JsonIgnore]
    public string Detail => "bad";

    [JsonIgnore]
    public string Version => "v1";
}

internal sealed class CapturingLogger<T> : ILogger<T>
{
    public List<string> Messages { get; } = [];

    public IDisposable? BeginScope<TState>(TState state)
        where TState : notnull => null;

    public bool IsEnabled(LogLevel logLevel) => true;

    public void Log<TState>(
        LogLevel logLevel,
        EventId eventId,
        TState state,
        Exception? exception,
        Func<TState, Exception?, string> formatter) => Messages.Add(formatter(state, exception));
}
