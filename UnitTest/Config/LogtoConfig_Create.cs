using AtomiCloud.Diene.AuthEngine.Config;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Config;

public class LogtoConfig_Create
{
    private static LogtoManagementConfig Management() =>
        LogtoManagementConfig.Create(
            "https://idp.test.invalid",
            "https://idp.test.invalid/api",
            "client",
            "secret").Get();

    [Fact]
    public void Accepts_a_canonical_origin_and_trims_identifiers()
    {
        var config = LogtoConfig.Create(
            " https://idp.test.invalid ",
            " https://idp.test.invalid/oidc ",
            " app ",
            "app-secret",
            Management());

        var value = config.Get();
        value.Endpoint.Should().Be(new Uri("https://idp.test.invalid"));
        value.Issuer.Should().Be("https://idp.test.invalid/oidc");
        value.AppId.Should().Be("app");
    }

    [Fact]
    public void Preserves_a_secret_verbatim_rather_than_trimming_it()
    {
        // A secret's surrounding whitespace may be significant, so it is stored as given
        // while the blank check still rejects an all-whitespace value.
        var config = LogtoConfig.Create(
            "https://idp.test.invalid",
            "https://idp.test.invalid/oidc",
            "app",
            " secret-with-spaces ",
            Management());

        config.Get().AppSecret.Should().Be(" secret-with-spaces ");
    }

    [Theory]
    [InlineData("https://user:pw@idp.test.invalid", "credentials")]
    [InlineData("https://idp.test.invalid/some/path", "canonical origin")]
    [InlineData("https://idp.test.invalid/?q=1", "canonical origin")]
    [InlineData("https://idp.test.invalid/#frag", "canonical origin")]
    public void Rejects_a_non_canonical_endpoint(string endpoint, string expectedReason)
    {
        var config = LogtoConfig.Create(
            endpoint,
            "https://idp.test.invalid/oidc",
            "app",
            "secret",
            Management());

        var error = config.GetFailure();
        error.Field.Should().Be("logto.endpoint");
        error.Reason.Should().Contain(expectedReason);
    }

    [Fact]
    public void Rejects_a_non_http_endpoint_scheme()
    {
        var config = LogtoConfig.Create(
            "ftp://idp.test.invalid",
            "https://idp.test.invalid/oidc",
            "app",
            "secret",
            Management());

        config.GetFailure().Reason.Should().Contain("http or https");
    }

    [Fact]
    public void Rejects_an_unparseable_endpoint()
    {
        var config = LogtoConfig.Create(
            "not-a-uri",
            "https://idp.test.invalid/oidc",
            "app",
            "secret",
            Management());

        config.GetFailure().Reason.Should().Contain("absolute URI");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("  ")]
    public void Rejects_a_blank_endpoint(string? endpoint)
    {
        var config = LogtoConfig.Create(
            endpoint,
            "https://idp.test.invalid/oidc",
            "app",
            "secret",
            Management());

        config.GetFailure().Reason.Should().Contain("must not be blank");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("   ")]
    public void Rejects_a_blank_issuer(string? issuer)
    {
        var config = LogtoConfig.Create(
            "https://idp.test.invalid",
            issuer,
            "app",
            "secret",
            Management());

        config.GetFailure().Field.Should().Be("logto.issuer");
    }

    [Theory]
    [InlineData("relative/issuer")]
    [InlineData("ftp://idp.test.invalid/oidc")]
    public void Rejects_an_issuer_that_is_not_an_absolute_http_uri(string issuer)
    {
        var config = LogtoConfig.Create(
            "https://idp.test.invalid",
            issuer,
            "app",
            "secret",
            Management());

        var error = config.GetFailure();
        error.Field.Should().Be("logto.issuer");
        error.Reason.Should().Contain("absolute http or https URI");
    }

    [Fact]
    public void Rejects_a_blank_app_id()
    {
        var config = LogtoConfig.Create(
            "https://idp.test.invalid",
            "https://idp.test.invalid/oidc",
            "  ",
            "secret",
            Management());

        config.GetFailure().Field.Should().Be("logto.appId");
    }

    [Fact]
    public void Rejects_a_blank_app_secret()
    {
        var config = LogtoConfig.Create(
            "https://idp.test.invalid",
            "https://idp.test.invalid/oidc",
            "app",
            "   ",
            Management());

        config.GetFailure().Field.Should().Be("logto.appSecret");
    }

    [Fact]
    public void Rejects_a_missing_management_block()
    {
        var config = LogtoConfig.Create(
            "https://idp.test.invalid",
            "https://idp.test.invalid/oidc",
            "app",
            "secret",
            null);

        config.GetFailure().Field.Should().Be("logto.management");
    }
}
