namespace AtomiCloud.Diene.Interfaces.UnitTest.Meta;

/// <summary>
/// META tier — ASSERT THE ASSERTER. Every assertion helper and every contract suite
/// this library ships is proven to PASS on a known-good subject and to FAIL on a
/// known-bad one. A helper that cannot fail is not a test, it is decoration.
/// </summary>
public class AssertTheAsserterTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    [Fact]
    public void BeSeamErr_should_pass_on_the_expected_seam_and_id()
    {
        Result.Err<int, SeamError>(SeamErrors.NotFound("/tmp/a"))
            .Should().BeSeamErr(SeamKind.Vfs, "not_found")
            .Which.Data["path"].Should().Be("/tmp/a");
    }

    [Fact]
    public void BeSeamErr_should_fail_on_a_different_id()
    {
        var act = () => Result.Err<int, SeamError>(SeamErrors.NotFound("/tmp/a"))
            .Should().BeSeamErr(SeamKind.Vfs, "already_exists");

        act.Should().Throw<Exception>().WithMessage("*already_exists*not_found*");
    }

    [Fact]
    public void BeSeamErr_should_fail_on_a_different_seam()
    {
        var act = () => Result.Err<int, SeamError>(SeamErrors.NotFound("/tmp/a"))
            .Should().BeSeamErr(SeamKind.System, "not_found");

        act.Should().Throw<Exception>();
    }

    [Fact]
    public void BeSeamErr_should_fail_on_a_successful_result()
    {
        var act = () => Result.Ok<int, SeamError>(1).Should().BeSeamErr(SeamKind.Vfs, "not_found");

        act.Should().Throw<Exception>();
    }

    [Fact]
    public void BeSeamErr_should_reject_a_null_assertion_subject()
    {
        var act = () => SeamAssertionExtensions.BeSeamErr<int>(null!, SeamKind.Vfs, "not_found");

        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task BeConformant_should_pass_on_a_conformant_implementation()
    {
        var report = await SeamContracts.Vfs(new InMemoryVfs(Anchor), "/root");

        report.Should().BeConformant();
        report.Failures.Should().BeEmpty();
        report.ToString().Should().Contain("cases conformant");
    }

    [Fact]
    public async Task BeConformant_should_fail_on_an_implementation_that_always_fails()
    {
        var report = await SeamContracts.Vfs(new AlwaysFailingVfs(), "/root");

        report.Conformant.Should().BeFalse();
        report.Failures.Should().HaveCount(report.Cases.Count);
        report.ToString().Should().Contain("cases failed");

        var act = () => report.Should().BeConformant();
        act.Should().Throw<Exception>().WithMessage("*conformant*");
    }

    [Fact]
    public async Task BeConformant_should_fail_on_an_implementation_that_never_fails()
    {
        var report = await SeamContracts.Vfs(new AlwaysSucceedingVfs(), "/root");

        report.Conformant.Should().BeFalse();
        report.Failures.Should().NotBeEmpty();
        report.Cases.Should().Contain(one => one.Passed);
    }

    [Fact]
    public async Task BeConformant_should_fail_on_an_implementation_that_throws()
    {
        var report = await SeamContracts.Vfs(new ThrowingVfs(), "/root");

        report.Conformant.Should().BeFalse();
        report.Failures.Should().AllSatisfy(failure => failure.Should().Contain("threw InvalidOperationException"));
    }

    [Fact]
    public void HaveLogged_should_pass_on_a_matching_record()
    {
        var sink = new InMemoryLoggerSink();
        sink.Emit(new LogRecord(Anchor, LogLevel.Warning, "careful")).Should().BeOk();

        sink.Should().HaveLogged(LogLevel.Warning, "careful").Which.Timestamp.Should().Be(Anchor);
    }

    [Fact]
    public void HaveLogged_should_fail_on_a_different_level_or_message()
    {
        var sink = new InMemoryLoggerSink();
        sink.Emit(new LogRecord(Anchor, LogLevel.Warning, "careful"));

        var level = () => sink.Should().HaveLogged(LogLevel.Error, "careful");
        var message = () => sink.Should().HaveLogged(LogLevel.Warning, "other");

        level.Should().Throw<Exception>().WithMessage("*error*careful*");
        message.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveLogged_should_fail_on_an_empty_sink()
    {
        var act = () => new InMemoryLoggerSink().Should().HaveLogged(LogLevel.Info, "anything");

        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveSampled_should_pass_on_a_matching_sample()
    {
        var collector = new InMemoryMetricsCollector();
        collector.Emit(new MetricRecord(Anchor, "app.count", MetricKind.Counter, 1)).Should().BeOk();

        collector.Should().HaveSampled("app.count", MetricKind.Counter, 1).Which.Unit.IsNone().Should().BeTrue();
    }

    [Fact]
    public void HaveSampled_should_fail_on_a_different_name_kind_or_value()
    {
        var collector = new InMemoryMetricsCollector();
        collector.Emit(new MetricRecord(Anchor, "app.count", MetricKind.Counter, 1));

        var name = () => collector.Should().HaveSampled("app.other", MetricKind.Counter, 1);
        var kind = () => collector.Should().HaveSampled("app.count", MetricKind.Gauge, 1);
        var value = () => collector.Should().HaveSampled("app.count", MetricKind.Counter, 2);

        name.Should().Throw<Exception>();
        kind.Should().Throw<Exception>().WithMessage("*gauge*app.count*");
        value.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveSampled_should_fail_on_an_empty_collector()
    {
        var act = () => new InMemoryMetricsCollector().Should().HaveSampled("app.count", MetricKind.Counter, 1);

        act.Should().Throw<Exception>();
    }

    [Fact]
    public void A_contract_case_should_render_its_outcome()
    {
        new ContractCase("case", Option.None<string>()).ToString().Should().Be("case: ok");
        new ContractCase("case", Option.Some("boom")).ToString().Should().Be("case: boom");
        new ContractCase("case", Option.Some("boom")).Passed.Should().BeFalse();
    }
}
