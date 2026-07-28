using AtomiCloud.Diene.ServerEngine.Config;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Config;

public class WebhookConfig_Create
{
    [Fact]
    public void It_should_default_to_the_contract_window()
    {
        // Assert
        WebhookConfig.MaximumTolerance.Should().Be(TimeSpan.FromMinutes(5));
        WebhookConfig.Default.Tolerance.Should().Be(WebhookConfig.MaximumTolerance);
    }

    [Theory]
    [ClassData(typeof(AcceptedToleranceCases))]
    public void It_should_accept_a_tolerance_at_or_below_the_maximum(TimeSpan tolerance)
    {
        // Act
        var actual = WebhookConfig.Create(tolerance);

        // Assert
        actual.Get().Tolerance.Should().Be(tolerance);
    }

    [Theory]
    [ClassData(typeof(NonPositiveToleranceCases))]
    public void It_should_reject_a_non_positive_tolerance(TimeSpan tolerance)
    {
        // Act
        var actual = WebhookConfig.Create(tolerance);

        // Assert
        actual.GetFailure().Field.Should().Be("webhooks.tolerance");
        actual.GetFailure().Reason.Should().Contain("must be positive");
    }

    [Fact]
    public void It_should_refuse_to_widen_the_window_past_the_contract_maximum()
    {
        // Act — a receiver asking for ten minutes is told so rather than silently clamped.
        var actual = WebhookConfig.Create(TimeSpan.FromMinutes(10));

        // Assert
        actual.GetFailure().Field.Should().Be("webhooks.tolerance");
        actual.GetFailure().Reason.Should().Contain("must not exceed the C0 maximum of 300 seconds");
    }

    [Fact]
    public void It_should_reject_a_tolerance_one_tick_above_the_maximum()
    {
        // Act
        var actual = WebhookConfig.Create(WebhookConfig.MaximumTolerance + TimeSpan.FromTicks(1));

        // Assert
        actual.IsFailure().Should().BeTrue();
    }

    private sealed class AcceptedToleranceCases : TheoryData<TimeSpan>
    {
        public AcceptedToleranceCases()
        {
            this.Add(TimeSpan.FromTicks(1));
            this.Add(TimeSpan.FromSeconds(30));
            this.Add(WebhookConfig.MaximumTolerance);
        }
    }

    private sealed class NonPositiveToleranceCases : TheoryData<TimeSpan>
    {
        public NonPositiveToleranceCases()
        {
            this.Add(TimeSpan.Zero);
            this.Add(TimeSpan.FromSeconds(-1));
        }
    }
}
