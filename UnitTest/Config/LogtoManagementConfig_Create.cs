using AtomiCloud.Diene.AuthEngine.Config;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Config;

public class LogtoManagementConfig_Create
{
    [Fact]
    public void Accepts_and_trims_a_valid_block()
    {
        var config = LogtoManagementConfig.Create(
            "https://idp.test.invalid",
            " https://idp.test.invalid/api ",
            " client ",
            "secret");

        var value = config.Get();
        value.Endpoint.Should().Be(new Uri("https://idp.test.invalid"));
        value.Resource.Should().Be("https://idp.test.invalid/api");
        value.ClientId.Should().Be("client");
        value.ClientSecret.Should().Be("secret");
    }

    [Fact]
    public void Rejects_a_non_canonical_endpoint()
    {
        var config = LogtoManagementConfig.Create(
            "https://idp.test.invalid/path",
            "https://idp.test.invalid/api",
            "client",
            "secret");

        config.GetFailure().Field.Should().Be("logto.management.endpoint");
    }

    [Fact]
    public void Rejects_a_blank_resource()
    {
        var config = LogtoManagementConfig.Create(
            "https://idp.test.invalid",
            "  ",
            "client",
            "secret");

        config.GetFailure().Field.Should().Be("logto.management.resource");
    }

    [Fact]
    public void Rejects_a_blank_client_id()
    {
        var config = LogtoManagementConfig.Create(
            "https://idp.test.invalid",
            "https://idp.test.invalid/api",
            "",
            "secret");

        config.GetFailure().Field.Should().Be("logto.management.clientId");
    }

    [Fact]
    public void Rejects_a_blank_client_secret()
    {
        var config = LogtoManagementConfig.Create(
            "https://idp.test.invalid",
            "https://idp.test.invalid/api",
            "client",
            "   ");

        config.GetFailure().Field.Should().Be("logto.management.clientSecret");
    }
}
