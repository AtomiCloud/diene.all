using System.Net;
using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Client;

public class LogtoCredentialClient_RefreshAndRevoke
{
    private const string Resource = "https://api.test.invalid";

    private static (LogtoCredentialClient Client, StubHttpMessageHandler Handler, HttpClient Http) Build()
    {
        var handler = new StubHttpMessageHandler();
        var http = new HttpClient(handler);
        var client = new LogtoCredentialClient(http, AuthEngineFixture.Config(), AuthEngineFixture.Clock());
        return (client, handler, http);
    }

    [Fact]
    public async Task Refresh_returns_the_rotated_refresh_token()
    {
        // Rotation is what makes reuse detection able to catch a stolen token, so the
        // replacement must reach the caller to be stored in place of the old one.
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(
            HttpStatusCode.OK,
            """{"access_token":"at-2","refresh_token":"rt-2","expires_in":600}""");

        var outcome = await client.RefreshAsync("rt-1", Resource, TestContext.Current.CancellationToken);

        var refreshed = outcome.Get();
        refreshed.Access.Token.Should().Be("at-2");
        refreshed.RefreshToken.Should().Be("rt-2");
    }

    [Fact]
    public async Task Refresh_sends_the_refresh_token_grant()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"access_token":"at-2","refresh_token":"rt-2","expires_in":600}""");

        await client.RefreshAsync("rt-1", Resource, TestContext.Current.CancellationToken);

        var body = handler.CapturedBodies.Single();
        body.Should().Contain("grant_type=refresh_token");
        body.Should().Contain("refresh_token=rt-1");
    }

    [Fact]
    public async Task Refresh_keeps_the_presented_token_when_the_idp_declines_to_rotate()
    {
        // Blanking the stored credential because the response omitted a replacement
        // would log the user out on a successful refresh.
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"access_token":"at-2","expires_in":600}""");

        var outcome = await client.RefreshAsync("rt-1", Resource, TestContext.Current.CancellationToken);

        outcome.Get().RefreshToken.Should().Be("rt-1");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("   ")]
    public async Task Refresh_refuses_a_blank_refresh_token(string? token)
    {
        var (client, _, http) = Build();
        using var __ = http;

        var outcome = await client.RefreshAsync(token!, Resource, TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("missing or malformed");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("  ")]
    public async Task Refresh_refuses_a_blank_resource(string? resource)
    {
        var (client, _, http) = Build();
        using var __ = http;

        var outcome = await client.RefreshAsync("rt-1", resource!, TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("not issued for this resource");
    }

    [Fact]
    public async Task Refresh_propagates_a_refusal()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondStatus(HttpStatusCode.Unauthorized);

        var outcome = await client.RefreshAsync("rt-1", Resource, TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("client credentials were rejected");
    }

    [Fact]
    public async Task Refresh_refuses_a_response_with_no_access_token()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"refresh_token":"rt-2"}""");

        var outcome = await client.RefreshAsync("rt-1", Resource, TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("missing or malformed");
    }

    [Fact]
    public async Task Revoke_acquires_a_management_token_then_deletes_the_sessions()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"access_token":"mgmt-1","expires_in":600}""");
        handler.RespondStatus(HttpStatusCode.NoContent);

        var outcome = await client.RevokeUserSessionsAsync("user-9", TestContext.Current.CancellationToken);

        outcome.IsSuccess().Should().BeTrue();
        handler.Requests.Should().HaveCount(2);

        var tokenBody = handler.CapturedBodies[0];
        tokenBody.Should().Contain("client_id=management-client");
        tokenBody.Should().Contain("grant_type=client_credentials");

        var revoke = handler.Requests[1];
        revoke.Method.Should().Be(HttpMethod.Delete);
        revoke.RequestUri!.AbsoluteUri.Should().Be("https://idp.test.invalid/api/users/user-9/sessions");
        revoke.Headers.Authorization!.Scheme.Should().Be("Bearer");
        revoke.Headers.Authorization.Parameter.Should().Be("mgmt-1");
    }

    [Fact]
    public async Task Revoke_escapes_a_user_id_carrying_path_characters()
    {
        // An unescaped id would let a caller-supplied value alter the request path.
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"access_token":"mgmt-1","expires_in":600}""");
        handler.RespondStatus(HttpStatusCode.NoContent);

        await client.RevokeUserSessionsAsync("a/../b", TestContext.Current.CancellationToken);

        handler.Requests[1].RequestUri!.AbsoluteUri
            .Should().Be("https://idp.test.invalid/api/users/a%2F..%2Fb/sessions");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("   ")]
    public async Task Revoke_refuses_a_blank_user_id(string? userId)
    {
        var (client, _, http) = Build();
        using var __ = http;

        var outcome = await client.RevokeUserSessionsAsync(userId!, TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("missing or malformed");
    }

    [Fact]
    public async Task Revoke_propagates_a_management_token_failure_without_calling_delete()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondStatus(HttpStatusCode.Unauthorized);

        var outcome = await client.RevokeUserSessionsAsync("user-9", TestContext.Current.CancellationToken);

        outcome.IsFailure().Should().BeTrue();
        handler.Requests.Should().ContainSingle();
    }

    [Fact]
    public async Task Revoke_refuses_when_the_management_token_response_carries_no_token()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"expires_in":600}""");

        var outcome = await client.RevokeUserSessionsAsync("user-9", TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("missing or malformed");
        handler.Requests.Should().ContainSingle();
    }

    [Fact]
    public async Task Revoke_reports_a_failed_delete()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"access_token":"mgmt-1","expires_in":600}""");
        handler.RespondStatus(HttpStatusCode.NotFound);

        var outcome = await client.RevokeUserSessionsAsync("user-9", TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("404");
    }

    [Fact]
    public async Task Revoke_converts_a_delete_transport_failure_into_a_typed_result()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"access_token":"mgmt-1","expires_in":600}""");
        handler.RespondTransportFailure();

        var outcome = await client.RevokeUserSessionsAsync("user-9", TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("could not be reached");
    }

    [Fact]
    public async Task Revoke_converts_a_delete_timeout_into_a_typed_result()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"access_token":"mgmt-1","expires_in":600}""");
        handler.RespondTimeout();

        var outcome = await client.RevokeUserSessionsAsync("user-9", TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("could not be reached");
    }
}
