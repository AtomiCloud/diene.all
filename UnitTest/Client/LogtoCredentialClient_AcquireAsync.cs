using System.Net;
using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Client;

public class LogtoCredentialClient_AcquireAsync
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
    public async Task Acquires_a_token_and_resolves_expiry_against_the_injected_clock()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(
            HttpStatusCode.OK,
            """{"access_token":"at-1","expires_in":600,"token_type":"Bearer"}""");

        var outcome = await client.AcquireAsync(Resource, ["notes:read"], TestContext.Current.CancellationToken);

        var token = outcome.Get();
        token.Token.Should().Be("at-1");
        token.ExpiresAt.Should().Be(AuthEngineFixture.Now.AddSeconds(600));
    }

    [Fact]
    public async Task Sends_the_client_credentials_grant_with_resource_and_scope()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"access_token":"at-1","expires_in":600}""");

        await client.AcquireAsync(Resource, ["notes:read", "notes:write"], TestContext.Current.CancellationToken);

        var body = handler.CapturedBodies.Should().ContainSingle().Subject;
        body.Should().Contain("grant_type=client_credentials");
        body.Should().Contain("client_id=app");
        body.Should().Contain(Uri.EscapeDataString(Resource));

        // Form encoding renders a space as "+", not "%20", so the scope list is asserted
        // in the encoding the wire actually carries rather than in Uri.EscapeDataString's.
        body.Should().Contain("scope=notes%3Aread+notes%3Awrite");

        handler.Requests.Single().RequestUri!.AbsoluteUri
            .Should().Be("https://idp.test.invalid/oidc/token");
    }

    [Fact]
    public async Task Omits_the_scope_parameter_when_no_scopes_are_requested()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"access_token":"at-1","expires_in":600}""");

        await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken);

        handler.CapturedBodies.Single().Should().NotContain("scope=");
    }

    [Fact]
    public async Task Falls_back_to_the_configured_lifetime_when_expires_in_is_absent()
    {
        // Treating a missing expires_in as "already expired" would make the cache
        // re-acquire on every single call, so the configured access lifetime is used.
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"access_token":"at-1"}""");

        var outcome = await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken);

        outcome.Get().ExpiresAt.Should().Be(AuthEngineFixture.Now.AddMinutes(10));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("  ")]
    public async Task Refuses_a_blank_resource(string? resource)
    {
        var (client, _, http) = Build();
        using var __ = http;

        var outcome = await client.AcquireAsync(resource!, [], TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("not issued for this resource");
    }

    [Fact]
    public async Task Reports_rejected_credentials_distinctly_from_a_generic_refusal()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondStatus(HttpStatusCode.Unauthorized);

        var outcome = await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("client credentials were rejected");
    }

    [Fact]
    public async Task Carries_the_status_code_for_an_unmapped_refusal()
    {
        // The status travels in the detail so diagnosing does not require re-running.
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondStatus(HttpStatusCode.ServiceUnavailable);

        var outcome = await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("503");
    }

    [Fact]
    public async Task Maps_a_forbidden_response_to_an_authorization_failure()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondStatus(HttpStatusCode.Forbidden);

        var outcome = await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken);

        outcome.GetFailure().Id.Should().Be("unauthorized");
    }

    [Fact]
    public async Task Converts_a_transport_failure_into_a_typed_result()
    {
        // Never an exception: a caller composing this into a Result pipeline must not
        // need a try/catch to stay total.
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondTransportFailure();

        var outcome = await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("could not be reached");
    }

    [Fact]
    public async Task Converts_a_timeout_into_a_typed_result()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondTimeout();

        var outcome = await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("could not be reached");
    }

    [Fact]
    public async Task Refuses_a_response_carrying_no_access_token()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, """{"expires_in":600}""");

        var outcome = await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("missing or malformed");
    }

    [Fact]
    public async Task Refuses_a_response_body_that_is_not_json()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.Respond(_ => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent("not json", System.Text.Encoding.UTF8, "application/json"),
        });

        var outcome = await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("missing or malformed");
    }

    [Fact]
    public async Task Refuses_a_json_null_response_body()
    {
        var (client, handler, http) = Build();
        using var _ = http;
        handler.RespondJson(HttpStatusCode.OK, "null");

        var outcome = await client.AcquireAsync(Resource, [], TestContext.Current.CancellationToken);

        outcome.GetFailure().Detail.Should().Contain("missing or malformed");
    }

    [Fact]
    public void Rejects_null_construction_arguments()
    {
        using var http = new HttpClient(new StubHttpMessageHandler());
        var config = AuthEngineFixture.Config();
        var clock = AuthEngineFixture.Clock();

        FluentActions.Invoking(() => new LogtoCredentialClient(null!, config, clock))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new LogtoCredentialClient(http, null!, clock))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new LogtoCredentialClient(http, config, null!))
            .Should().Throw<ArgumentNullException>();
    }
}
