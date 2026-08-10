using AtomiCloud.Diene.AuthEngine.Config;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Config;

public class AuthEngineConfig_Create
{
    private static LogtoManagementConfig Management() =>
        LogtoManagementConfig.Create(
            "https://idp.test.invalid",
            "https://idp.test.invalid/api",
            "client",
            "secret").Get();

    private static LogtoConfig Logto() =>
        LogtoConfig.Create(
            "https://idp.test.invalid",
            "https://idp.test.invalid/oidc",
            "app",
            "app-secret",
            Management()).Get();

    [Fact]
    public void Accepts_a_fully_populated_configuration()
    {
        var config = AuthEngineConfig.Create(
            Logto(),
            HandoffConfig.Default,
            TokenLifetimeConfig.Default,
            "home_landscape");

        var value = config.Get();
        value.HomeLandscapeClaim.Should().Be("home_landscape");
        value.Handoff.Mount.Should().Be("/app-handoff");
        value.Logto.Issuer.Should().Be("https://idp.test.invalid/oidc");
    }

    [Fact]
    public void Trims_the_home_landscape_claim_name()
    {
        var config = AuthEngineConfig.Create(
            Logto(),
            HandoffConfig.Default,
            TokenLifetimeConfig.Default,
            "  home_landscape  ");

        config.Get().HomeLandscapeClaim.Should().Be("home_landscape");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Rejects_a_blank_home_landscape_claim(string? claim)
    {
        var config = AuthEngineConfig.Create(
            Logto(),
            HandoffConfig.Default,
            TokenLifetimeConfig.Default,
            claim);

        config.GetFailure().Field.Should().Be("homeLandscapeClaim");
    }

    [Fact]
    public void Rejects_a_missing_logto_block()
    {
        var config = AuthEngineConfig.Create(
            null,
            HandoffConfig.Default,
            TokenLifetimeConfig.Default,
            "home_landscape");

        config.GetFailure().Field.Should().Be("logto");
    }

    [Fact]
    public void Rejects_a_missing_handoff_block()
    {
        var config = AuthEngineConfig.Create(Logto(), null, TokenLifetimeConfig.Default, "home_landscape");

        config.GetFailure().Field.Should().Be("handoff");
    }

    [Fact]
    public void Rejects_a_missing_lifetimes_block()
    {
        var config = AuthEngineConfig.Create(Logto(), HandoffConfig.Default, null, "home_landscape");

        config.GetFailure().Field.Should().Be("lifetimes");
    }

    [Fact]
    public void Renders_a_config_error_as_field_and_reason()
    {
        var error = new ConfigError("logto.appId", "App id must not be blank.");

        error.ToString().Should().Be("logto.appId: App id must not be blank.");
    }
}
