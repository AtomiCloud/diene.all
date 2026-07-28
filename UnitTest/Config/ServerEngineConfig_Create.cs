using AtomiCloud.Diene.ServerEngine.Config;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Config;

public class ServerEngineConfig_Create
{
    [Fact]
    public void It_should_expose_the_conventional_block_key()
    {
        // Assert
        ServerEngineConfig.Key.Should().Be("ServerEngine");
    }

    [Fact]
    public void It_should_hold_both_validated_sections()
    {
        // Arrange
        var identity = Identity();
        var webhooks = WebhookConfig.Default;

        // Act
        var actual = ServerEngineConfig.Create(identity, webhooks).Get();

        // Assert
        actual.Identity.Should().BeSameAs(identity);
        actual.Webhooks.Should().BeSameAs(webhooks);
    }

    [Fact]
    public void It_should_reject_a_missing_identity()
    {
        // Act
        var actual = ServerEngineConfig.Create(null, WebhookConfig.Default);

        // Assert
        actual.GetFailure().Field.Should().Be("identity");
        actual.GetFailure().Reason.Should().Contain("required");
    }

    [Fact]
    public void It_should_reject_missing_webhook_settings()
    {
        // Act
        var actual = ServerEngineConfig.Create(Identity(), null);

        // Assert
        actual.GetFailure().Field.Should().Be("webhooks");
        actual.GetFailure().Reason.Should().Contain("required");
    }

    private static ServiceIdentityConfig Identity() =>
        ServiceIdentityConfig.Create("lapras", "sulfoxide", "demo", "api", "1.0.0").Get();
}

public class ServerEngineConfigError_ToString
{
    [Fact]
    public void It_should_render_the_field_and_reason_on_one_line()
    {
        // Arrange
        var subject = new ServerEngineConfigError("webhooks.tolerance", "Tolerance must be positive.");

        // Act
        var actual = subject.ToString();

        // Assert
        actual.Should().Be("webhooks.tolerance: Tolerance must be positive.");
    }
}
