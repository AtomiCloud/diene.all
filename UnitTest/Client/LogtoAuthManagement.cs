using System.Net;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.AuthEngine;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using FluentAssertions;
using ManagementClient = AtomiCloud.Diene.AuthEngine.Client.LogtoAuthManagement;

namespace AtomiCloud.DotnetBase.UnitTest.Client;

public class LogtoAuthManagement
{
    [Fact]
    public async Task Gets_one_percent_encoded_user_and_projects_the_security_fields()
    {
        var handler = new StubHttpMessageHandler();
        RespondWithToken(handler);
        handler.RespondJson(
            HttpStatusCode.OK,
            """{"id":"ignored","primaryEmail":"owner@example.invalid","isSuspended":false}""");
        using var http = new HttpClient(handler);
        var client = new ManagementClient(http, AuthEngineFixture.Config());

        var outcome = await client.GetUser("user/with space", TestContext.Current.CancellationToken);

        outcome.Get().Get().Should().Be(new AuthManagementUser(
            "user/with space",
            "owner@example.invalid",
            false));
        handler.Requests.Should().HaveCount(2);
        handler.Requests[0].RequestUri!.AbsolutePath.Should().Be("/oidc/token");
        handler.Requests[1].RequestUri!.AbsoluteUri.Should().Contain("/api/users/user%2Fwith%20space");
        handler.Requests[1].Headers.Authorization!.ToString().Should().Be("Bearer management-token");
        handler.Requests.Count(request => request.Method == HttpMethod.Get).Should().Be(1);
    }

    [Fact]
    public async Task Returns_none_only_for_a_user_404()
    {
        var handler = new StubHttpMessageHandler();
        RespondWithToken(handler);
        handler.RespondStatus(HttpStatusCode.NotFound);
        using var http = new HttpClient(handler);
        var client = new ManagementClient(http, AuthEngineFixture.Config());

        var outcome = await client.GetUser("deleted", TestContext.Current.CancellationToken);

        outcome.Get().IsNone().Should().BeTrue();
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"primaryEmail\":null}")]
    [InlineData("not-json")]
    [InlineData("null")]
    public async Task Rejects_a_malformed_user_document(string json)
    {
        var handler = new StubHttpMessageHandler();
        RespondWithToken(handler);
        handler.RespondJson(HttpStatusCode.OK, json);
        using var http = new HttpClient(handler);
        var client = new ManagementClient(http, AuthEngineFixture.Config());

        (await client.GetUser("user-1", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task Mints_the_exact_Logto_sign_in_payload()
    {
        var handler = new StubHttpMessageHandler();
        RespondWithToken(handler);
        handler.RespondJson(HttpStatusCode.Created, """{"token":"ott-1","id":"id-1"}""");
        using var http = new HttpClient(handler);
        var client = new ManagementClient(http, AuthEngineFixture.Config());

        var outcome = await client.MintOneTimeToken(
            "owner@example.invalid",
            TestContext.Current.CancellationToken);

        outcome.Get().Should().Be("ott-1");
        handler.Requests[1].Method.Should().Be(HttpMethod.Post);
        handler.Requests[1].RequestUri!.AbsolutePath.Should().Be("/api/one-time-tokens");
        JsonNode.DeepEquals(
                JsonNode.Parse(handler.CapturedBodies[1]),
                JsonNode.Parse(
                    """{"email":"owner@example.invalid","expiresIn":120,"context":{"interactionEvent":"SignIn"}}"""))
            .Should().BeTrue();

        var tokenForm = handler.CapturedBodies[0];
        tokenForm.Should().Contain("grant_type=client_credentials")
            .And.Contain("client_id=management-client")
            .And.Contain("client_secret=management-secret")
            .And.Contain("resource=https%3A%2F%2Fidp.test.invalid%2Fapi")
            .And.Contain("scope=all");
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"token\":\"  \"}")]
    [InlineData("not-json")]
    [InlineData("null")]
    public async Task Rejects_a_missing_or_malformed_one_time_token(string json)
    {
        var handler = new StubHttpMessageHandler();
        RespondWithToken(handler);
        handler.RespondJson(HttpStatusCode.Created, json);
        using var http = new HttpClient(handler);
        var client = new ManagementClient(http, AuthEngineFixture.Config());

        (await client.MintOneTimeToken("owner@example.invalid", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task Claim_changes_read_modify_write_without_clobbering_other_custom_data()
    {
        var setHandler = new StubHttpMessageHandler();
        RespondWithToken(setHandler);
        setHandler.RespondJson(HttpStatusCode.OK, """{"kept":42}""");
        setHandler.RespondJson(HttpStatusCode.OK, "{}");
        using var setHttp = new HttpClient(setHandler);
        var setClient = new ManagementClient(setHttp, AuthEngineFixture.Config());

        (await setClient.SetClaim(
            "user-1",
            "home_landscape",
            "lapras",
            TestContext.Current.CancellationToken)).IsSuccess().Should().BeTrue();

        setHandler.Requests[1].Method.Should().Be(HttpMethod.Get);
        setHandler.Requests[2].Method.Should().Be(HttpMethod.Patch);
        setHandler.Requests[2].RequestUri!.AbsolutePath.Should().Be("/api/users/user-1/custom-data");
        JsonNode.DeepEquals(
                JsonNode.Parse(setHandler.CapturedBodies[2]),
                JsonNode.Parse("""{"customData":{"kept":42,"home_landscape":"lapras"}}"""))
            .Should().BeTrue();

        var removeHandler = new StubHttpMessageHandler();
        RespondWithToken(removeHandler);
        removeHandler.RespondJson(
            HttpStatusCode.OK,
            """{"kept":42,"home_landscape":"lapras"}""");
        removeHandler.RespondStatus(HttpStatusCode.OK);
        using var removeHttp = new HttpClient(removeHandler);
        var removeClient = new ManagementClient(removeHttp, AuthEngineFixture.Config());

        (await removeClient.RemoveClaim(
            "user-1",
            "home_landscape",
            TestContext.Current.CancellationToken)).IsSuccess().Should().BeTrue();

        JsonNode.DeepEquals(
                JsonNode.Parse(removeHandler.CapturedBodies[2]),
                JsonNode.Parse("""{"customData":{"kept":42}}"""))
            .Should().BeTrue();
    }

    [Fact]
    public async Task Implements_role_add_remove_and_user_delete_with_Logto_routes()
    {
        var handler = new StubHttpMessageHandler();
        RespondWithToken(handler);
        handler.RespondStatus(HttpStatusCode.Created);
        RespondWithToken(handler);
        handler.RespondStatus(HttpStatusCode.NoContent);
        RespondWithToken(handler);
        handler.RespondStatus(HttpStatusCode.NoContent);
        using var http = new HttpClient(handler);
        var client = new ManagementClient(http, AuthEngineFixture.Config());

        (await client.AssignRole("user-1", "role/a", TestContext.Current.CancellationToken))
            .IsSuccess().Should().BeTrue();
        (await client.RemoveRole("user-1", "role/a", TestContext.Current.CancellationToken))
            .IsSuccess().Should().BeTrue();
        (await client.DeleteUser("user-1", TestContext.Current.CancellationToken))
            .IsSuccess().Should().BeTrue();

        handler.Requests[1].RequestUri!.AbsolutePath.Should().Be("/api/users/user-1/roles");
        JsonNode.DeepEquals(
                JsonNode.Parse(handler.CapturedBodies[1]),
                JsonNode.Parse("""{"roleIds":["role/a"]}"""))
            .Should().BeTrue();
        handler.Requests[3].RequestUri!.AbsoluteUri.Should().Contain("/api/users/user-1/roles/role%2Fa");
        handler.Requests[5].RequestUri!.AbsolutePath.Should().Be("/api/users/user-1");
    }

    [Fact]
    public async Task Rejects_blank_inputs_before_any_network_call()
    {
        var handler = new StubHttpMessageHandler();
        using var http = new HttpClient(handler);
        var client = new ManagementClient(http, AuthEngineFixture.Config());
        var cancellationToken = TestContext.Current.CancellationToken;

        (await client.GetUser(" ", cancellationToken)).IsFailure().Should().BeTrue();
        (await client.MintOneTimeToken("", cancellationToken)).IsFailure().Should().BeTrue();
        (await client.SetClaim("", "key", "value", cancellationToken)).IsFailure().Should().BeTrue();
        (await client.SetClaim("user", "key", " ", cancellationToken)).IsFailure().Should().BeTrue();
        (await client.RemoveClaim("user", "", cancellationToken)).IsFailure().Should().BeTrue();
        (await client.AssignRole("", "role", cancellationToken)).IsFailure().Should().BeTrue();
        (await client.RemoveRole("user", " ", cancellationToken)).IsFailure().Should().BeTrue();
        (await client.DeleteUser(" ", cancellationToken)).IsFailure().Should().BeTrue();
        handler.Requests.Should().BeEmpty();
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized, "configured client credentials")]
    [InlineData(HttpStatusCode.Forbidden, "lacks a required scope")]
    [InlineData(HttpStatusCode.ServiceUnavailable, "status 503")]
    public async Task Maps_management_token_HTTP_failures(HttpStatusCode status, string detail)
    {
        var handler = new StubHttpMessageHandler();
        handler.RespondStatus(status);
        using var http = new HttpClient(handler);
        var client = new ManagementClient(http, AuthEngineFixture.Config());

        var outcome = await client.MintOneTimeToken("owner@example.invalid", TestContext.Current.CancellationToken);

        outcome.IsFailure(out var problem).Should().BeTrue();
        problem!.Detail.Should().Contain(detail);
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"access_token\":\"\"}")]
    [InlineData("not-json")]
    [InlineData("null")]
    public async Task Rejects_a_malformed_management_token_document(string json)
    {
        var handler = new StubHttpMessageHandler();
        handler.RespondJson(HttpStatusCode.OK, json);
        using var http = new HttpClient(handler);
        var client = new ManagementClient(http, AuthEngineFixture.Config());

        (await client.MintOneTimeToken("owner@example.invalid", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task Maps_transport_failure_and_timeout_at_both_HTTP_stages()
    {
        var tokenTransport = new StubHttpMessageHandler();
        tokenTransport.RespondTransportFailure();
        using var tokenTransportHttp = new HttpClient(tokenTransport);
        var tokenTransportClient = new ManagementClient(
            tokenTransportHttp,
            AuthEngineFixture.Config());
        (await tokenTransportClient.MintOneTimeToken("a@b.test", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();

        var tokenTimeout = new StubHttpMessageHandler();
        tokenTimeout.RespondTimeout();
        using var tokenTimeoutHttp = new HttpClient(tokenTimeout);
        var tokenTimeoutClient = new ManagementClient(
            tokenTimeoutHttp,
            AuthEngineFixture.Config());
        (await tokenTimeoutClient.MintOneTimeToken("a@b.test", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();

        var apiTransport = new StubHttpMessageHandler();
        RespondWithToken(apiTransport);
        apiTransport.RespondTransportFailure();
        using var apiTransportHttp = new HttpClient(apiTransport);
        var apiTransportClient = new ManagementClient(
            apiTransportHttp,
            AuthEngineFixture.Config());
        (await apiTransportClient.GetUser("user-1", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();

        var apiTimeout = new StubHttpMessageHandler();
        RespondWithToken(apiTimeout);
        apiTimeout.RespondTimeout();
        using var apiTimeoutHttp = new HttpClient(apiTimeout);
        var apiTimeoutClient = new ManagementClient(
            apiTimeoutHttp,
            AuthEngineFixture.Config());
        (await apiTimeoutClient.GetUser("user-1", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task Maps_API_status_and_claim_read_or_write_failures()
    {
        var get = new StubHttpMessageHandler();
        RespondWithToken(get);
        get.RespondStatus(HttpStatusCode.ServiceUnavailable);
        using var getHttp = new HttpClient(get);
        (await new ManagementClient(getHttp, AuthEngineFixture.Config())
                .GetUser("user-1", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();

        var read = new StubHttpMessageHandler();
        RespondWithToken(read);
        read.RespondStatus(HttpStatusCode.NotFound);
        using var readHttp = new HttpClient(read);
        (await new ManagementClient(readHttp, AuthEngineFixture.Config())
                .SetClaim("user-1", "key", "value", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();

        var write = new StubHttpMessageHandler();
        RespondWithToken(write);
        write.RespondJson(HttpStatusCode.OK, "{}");
        write.RespondStatus(HttpStatusCode.Forbidden);
        using var writeHttp = new HttpClient(write);
        (await new ManagementClient(writeHttp, AuthEngineFixture.Config())
                .RemoveClaim("user-1", "key", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();

        var mutation = new StubHttpMessageHandler();
        RespondWithToken(mutation);
        mutation.RespondStatus(HttpStatusCode.BadRequest);
        using var mutationHttp = new HttpClient(mutation);
        (await new ManagementClient(mutationHttp, AuthEngineFixture.Config())
                .DeleteUser("user-1", TestContext.Current.CancellationToken))
            .IsFailure().Should().BeTrue();
    }

    [Fact]
    public void Constructor_rejects_null_dependencies()
    {
        using var http = new HttpClient(new StubHttpMessageHandler());
        FluentActions.Invoking(() => new ManagementClient(null!, AuthEngineFixture.Config()))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new ManagementClient(http, null!))
            .Should().Throw<ArgumentNullException>();
    }

    private static void RespondWithToken(StubHttpMessageHandler handler) =>
        handler.RespondJson(HttpStatusCode.OK, """{"access_token":"management-token","expires_in":600}""");
}
