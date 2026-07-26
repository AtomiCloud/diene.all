namespace AtomiCloud.DotnetBase.UnitTest;

public class OtelEnvironmentTests
{
    private static ExporterOption BothOn => new()
    {
        Console = new ConsoleExporterOption { Enabled = true },
        Otlp = new OtlpExporterOption { Enabled = true },
    };

    [Fact]
    public void HasValue_RejectsAbsentBlankAndNull()
    {
        OtelEnvironment.HasValue(Env.None, "OTEL_LOGS_EXPORTER").Should().BeFalse();
        OtelEnvironment.HasValue(Env.Of(("OTEL_LOGS_EXPORTER", "   ")), "OTEL_LOGS_EXPORTER").Should().BeFalse();
        OtelEnvironment.HasValue(Env.Of(("OTEL_LOGS_EXPORTER", null)), "OTEL_LOGS_EXPORTER").Should().BeFalse();
        OtelEnvironment.HasValue(Env.Of(("OTEL_LOGS_EXPORTER", "otlp")), "OTEL_LOGS_EXPORTER").Should().BeTrue();
    }

    [Fact]
    public void HasValue_RejectsANullEnvironment() =>
        FluentActions.Invoking(() => OtelEnvironment.HasValue(null!, "OTEL_SDK_DISABLED"))
            .Should().Throw<ArgumentNullException>();

    [Theory]
    [InlineData("true", true)]
    [InlineData("TRUE", true)]
    [InlineData("  true  ", true)]
    [InlineData("false", false)]
    [InlineData("1", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void IsSdkDisabled_OnlyHonoursTrue(string? value, bool expected) =>
        OtelEnvironment
            .IsSdkDisabled(Env.Of((OtelEnvironment.SdkDisabledVariable, value)))
            .Should().Be(expected);

    [Fact]
    public void IsSdkDisabled_IsFalseWhenUnset() => OtelEnvironment.IsSdkDisabled(Env.None).Should().BeFalse();

    [Fact]
    public void IsSdkDisabled_RejectsANullEnvironment() =>
        FluentActions.Invoking(() => OtelEnvironment.IsSdkDisabled(null!)).Should().Throw<ArgumentNullException>();

    [Fact]
    public void Exporters_DefersToTheBlockWhenTheOverrideIsUnsetOrBlank()
    {
        OtelEnvironment
            .Exporters(BothOn, OtelEnvironment.LogsExporterVariable, Env.None)
            .Should().Be(new ExporterSelection(true, true));

        OtelEnvironment
            .Exporters(BothOn, OtelEnvironment.LogsExporterVariable, Env.Of((OtelEnvironment.LogsExporterVariable, " ")))
            .Should().Be(new ExporterSelection(true, true));

        OtelEnvironment
            .Exporters(new ExporterOption(), OtelEnvironment.LogsExporterVariable, Env.None)
            .Should().Be(new ExporterSelection(false, false));
    }

    [Theory]
    [InlineData("none", false, false)]
    [InlineData("console,otlp", true, true)]
    [InlineData("console", true, false)]
    [InlineData("otlp", false, true)]
    [InlineData("OTLP", false, true)]
    [InlineData(" console , otlp ", true, true)]
    [InlineData("jaeger", false, false)]
    [InlineData("otlp,none", false, false)]
    public void Exporters_TreatsTheOverrideAsSetMembership(string value, bool console, bool otlp) =>
        OtelEnvironment
            .Exporters(BothOn, OtelEnvironment.TracesExporterVariable, Env.Of((OtelEnvironment.TracesExporterVariable, value)))
            .Should().Be(new ExporterSelection(console, otlp));

    [Fact]
    public void Exporters_RejectsNullArguments()
    {
        FluentActions.Invoking(() => OtelEnvironment.Exporters(null!, "OTEL_LOGS_EXPORTER", Env.None))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => OtelEnvironment.Exporters(BothOn, "OTEL_LOGS_EXPORTER", null!))
            .Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Process_ReadsTheHostEnvironment()
    {
        var environment = OtelEnvironment.Process();
        environment.Should().NotBeNull();
        environment.Keys.Should().OnlyHaveUniqueItems();
    }

    [Fact]
    public void VariableNames_AreTheStandardOtelSpellings()
    {
        OtelEnvironment.LogsExporterVariable.Should().Be("OTEL_LOGS_EXPORTER");
        OtelEnvironment.MetricsExporterVariable.Should().Be("OTEL_METRICS_EXPORTER");
        OtelEnvironment.TracesExporterVariable.Should().Be("OTEL_TRACES_EXPORTER");
        OtelEnvironment.OtlpEndpointVariable.Should().Be("OTEL_EXPORTER_OTLP_ENDPOINT");
        OtelEnvironment.ResourceAttributesVariable.Should().Be("OTEL_RESOURCE_ATTRIBUTES");
        OtelEnvironment.ServiceNameVariable.Should().Be("OTEL_SERVICE_NAME");
        OtelEnvironment.TracesSamplerVariable.Should().Be("OTEL_TRACES_SAMPLER");
        OtelEnvironment.SdkDisabledVariable.Should().Be("OTEL_SDK_DISABLED");
    }
}
