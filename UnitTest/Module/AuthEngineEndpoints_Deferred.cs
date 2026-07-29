using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.AuthEngine;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Module;
using AtomiCloud.Diene.AuthEngine.Policy;
using AtomiCloud.Diene.AuthEngine.TestHelper.Builders;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using FluentAssertions;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.UnitTest.Module;

public class AuthEngineEndpoints_Deferred
{
    [Fact]
    public async Task Mint_reads_sub_and_email_from_the_validated_session_and_sets_no_store()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config();
        var clock = AuthEngineFixture.Clock();
        var store = new InMemoryDeferredTokenStore(clock);
        var minter = new DeferredTokenMinter(store, new FakeAuthManagement(), clock);
        var context = JsonContext("{}");
        context.Request.Headers.Authorization = $"Bearer {issuer.MintValidFor(
            AuthEngineFixture.Subject,
            config.Logto.Issuer,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            extraClaims: new Dictionary<string, object> { ["email"] = "owner@example.invalid" })}";

        var result = await AuthEngineEndpoints.HandleMintAsync(
            context,
            new AuthGuard(AuthEngineFixture.Validator(issuer, clock, config)),
            config,
            minter);
        await context.Response.StartAsync(TestContext.Current.CancellationToken);

        result.Nonce.Should().HaveLength(43);
        store.Records.Values.Should().ContainSingle().Which.Payload
            .Should().Be(new DeferredPayload(AuthEngineFixture.Subject, "owner@example.invalid"));
        context.Response.Headers.CacheControl.ToString().Should().Be("no-store");
    }

    [Theory]
    [InlineData("{\"unexpected\":true}", "application/json")]
    [InlineData("[]", "application/json")]
    [InlineData("null", "application/json")]
    [InlineData("", "application/json")]
    [InlineData("{}", "text/plain")]
    public async Task Mint_rejects_any_request_other_than_an_empty_JSON_object(string body, string contentType)
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config();
        var context = JsonContext(body, contentType);
        context.Request.Headers.Authorization = $"Bearer {Token(issuer, config, includeEmail: true)}";
        var clock = AuthEngineFixture.Clock();

        var exception = await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleMintAsync(
                context,
                new AuthGuard(AuthEngineFixture.Validator(issuer, clock, config)),
                config,
                new DeferredTokenMinter(
                    new InMemoryDeferredTokenStore(clock),
                    new FakeAuthManagement(),
                    clock)))
            .Should().ThrowAsync<DomainProblemException>();

        exception.Which.Problem.Id.Should().Be("invalid_json");
        context.Response.Headers.CacheControl.ToString().Should().Be("no-store");
    }

    [Fact]
    public async Task Mint_rejects_missing_auth_email_guard_and_store_failures()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config();
        var clock = AuthEngineFixture.Clock();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, clock, config));

        var noBearer = await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleMintAsync(
                JsonContext("{}"),
                guard,
                config,
                new DeferredTokenMinter(new InMemoryDeferredTokenStore(clock), new FakeAuthManagement(), clock)))
            .Should().ThrowAsync<DomainProblemException>();
        noBearer.Which.Problem.Id.Should().Be("unauthenticated");

        var noEmailContext = JsonContext("{}");
        noEmailContext.Request.Headers.Authorization = $"Bearer {Token(issuer, config, includeEmail: false)}";
        var noEmail = await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleMintAsync(
                noEmailContext,
                guard,
                config,
                new DeferredTokenMinter(new InMemoryDeferredTokenStore(clock), new FakeAuthManagement(), clock)))
            .Should().ThrowAsync<DomainProblemException>();
        noEmail.Which.Problem.Id.Should().Be("unauthenticated");

        var expiredContext = JsonContext("{}");
        expiredContext.Request.Headers.Authorization = $"Bearer {Token(issuer, config, includeEmail: true)}";
        clock.Advance(TimeSpan.FromHours(1));
        var expired = await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleMintAsync(
                expiredContext,
                guard,
                config,
                new DeferredTokenMinter(new InMemoryDeferredTokenStore(clock), new FakeAuthManagement(), clock)))
            .Should().ThrowAsync<DomainProblemException>();
        expired.Which.Problem.Detail.Should().Contain("expired");

        var freshClock = AuthEngineFixture.Clock();
        var failedStore = new InMemoryDeferredTokenStore(freshClock);
        failedStore.FailNextPut(new AppHandoffExpired());
        var failedContext = JsonContext("{}");
        failedContext.Request.Headers.Authorization = $"Bearer {Token(issuer, config, includeEmail: true)}";
        var failed = await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleMintAsync(
                failedContext,
                new AuthGuard(AuthEngineFixture.Validator(issuer, freshClock, config)),
                config,
                new DeferredTokenMinter(failedStore, new FakeAuthManagement(), freshClock)))
            .Should().ThrowAsync<DomainProblemException>();
        failed.Which.Problem.Should().BeOfType<AppHandoffExpired>();
    }

    [Fact]
    public async Task Redeem_strictly_parses_device_telemetry_and_remaps_failures()
    {
        var success = new StubMinter
        {
            ExchangeOutcome = Result.Ok<DeferredExchange, IDomainProblem>(
                new DeferredExchange("ott", "owner@example.invalid", 120)),
        };
        var context = JsonContext(
            """{"nonce":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","device":{"platform":"android","appVersion":"1","osVersion":"2","model":"x"}}""");

        var response = await AuthEngineEndpoints.HandleRedeemAsync(context, success);
        await context.Response.StartAsync(TestContext.Current.CancellationToken);

        response.Should().Be(new DeferredExchange("ott", "owner@example.invalid", 120));
        success.Exchanged.Should().Equal("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
        context.Response.Headers.CacheControl.ToString().Should().Be("no-store");

        var failed = new StubMinter
        {
            ExchangeOutcome = Result.Err<DeferredExchange, IDomainProblem>(AuthProblems.IdentityProviderUnreachable()),
        };
        var failedContext = JsonContext(
            """{"nonce":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","device":{"platform":"ios"}}""");
        var exception = await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleRedeemAsync(failedContext, failed))
            .Should().ThrowAsync<DomainProblemException>();
        exception.Which.Problem.Should().BeOfType<AppHandoffExpired>();
    }

    [Theory]
    [InlineData("{\"nonce\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"device\":{\"platform\":\"android\",\"extra\":true}}", "application/json")]
    [InlineData("{\"nonce\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"device\":{\"platform\":\"Android\"}}", "application/json")]
    [InlineData("{\"nonce\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"device\":null}", "application/json")]
    [InlineData("{\"nonce\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"}", "application/json")]
    [InlineData("{\"nonce\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"device\":{\"platform\":\"ios\"},\"extra\":true}", "application/json")]
    [InlineData("null", "application/json")]
    [InlineData("[]", "application/json")]
    [InlineData("", "application/json")]
    [InlineData("{}", "text/plain")]
    public async Task Redeem_rejects_malformed_or_unknown_v1_input_with_one_problem(
        string body,
        string contentType)
    {
        var context = JsonContext(body, contentType);

        var exception = await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleRedeemAsync(
                context,
                new StubMinter()))
            .Should().ThrowAsync<DomainProblemException>();

        exception.Which.Problem.Should().BeOfType<AppHandoffExpired>();
        context.Response.Headers.CacheControl.ToString().Should().Be("no-store");
    }

    [Fact]
    public async Task Deferred_handlers_reject_null_dependencies()
    {
        using var issuer = AuthEngineFixture.NewIssuer();
        var config = AuthEngineFixture.Config();
        var guard = new AuthGuard(AuthEngineFixture.Validator(issuer, AuthEngineFixture.Clock(), config));
        var minter = new StubMinter();

        await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleMintAsync(null!, guard, config, minter))
            .Should().ThrowAsync<ArgumentNullException>();
        await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleMintAsync(JsonContext("{}"), null!, config, minter))
            .Should().ThrowAsync<ArgumentNullException>();
        await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleMintAsync(JsonContext("{}"), guard, null!, minter))
            .Should().ThrowAsync<ArgumentNullException>();
        await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleMintAsync(JsonContext("{}"), guard, config, null!))
            .Should().ThrowAsync<ArgumentNullException>();
        await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleRedeemAsync(null!, minter))
            .Should().ThrowAsync<ArgumentNullException>();
        await FluentActions.Awaiting(() => AuthEngineEndpoints.HandleRedeemAsync(JsonContext("{}"), null!))
            .Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task Problem_pipeline_renders_strict_redeem_failures_as_RFC_9457_with_no_store()
    {
        var config = AuthEngineFixture.Config();
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Services.AddAtomiProblems(
            new ProblemIdentity("lapras", "alcohol", "argon", "auth"),
            new ErrorPortalOption { Host = "errors.test.invalid" },
            catalog => catalog.AddBaseline().AddAtomiAuthEngineProblems(config));
        builder.Services.AddSingleton<IDeferredTokenMinter>(new StubMinter());
        builder.Services.AddAtomiAuthEngine(config);

        await using var app = builder.Build();
        app.UseExceptionHandler();
        app.MapAtomiAuthEngine(config);
        await app.StartAsync(TestContext.Current.CancellationToken);

        using var client = new HttpClient { BaseAddress = new Uri(app.Urls.Single()) };
        using var response = await client.PostAsync(
            "/app-handoff/redeem",
            new StringContent(
                """{"nonce":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","device":{"platform":"ios","unknown":true}}""",
                Encoding.UTF8,
                "application/json"),
            TestContext.Current.CancellationToken);

        response.StatusCode.Should().Be(HttpStatusCode.Gone);
        response.Headers.CacheControl!.NoStore.Should().BeTrue();
        var problem = JsonNode.Parse(await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken))!;
        problem["type"]!.GetValue<string>().Should().EndWith("/v1/app_handoff_expired");
        problem["title"]!.GetValue<string>().Should().Be("App handoff expired");
        problem["status"]!.GetValue<int>().Should().Be(410);
        problem["detail"]!.GetValue<string>().Should().Be("This app handoff is expired or invalid.");
        problem["data"]!.AsObject().Should().BeEmpty();

        await app.StopAsync(TestContext.Current.CancellationToken);
    }

    [Fact]
    public void Registers_the_problem_definition_at_the_configured_redeem_route()
    {
        var config = AuthEngineFixture.Config();
        var catalog = new ProblemCatalogBuilder().AddAtomiAuthEngineProblems(config).Build();
        var descriptor = catalog.Find("v1", "app_handoff_expired").Get();

        descriptor.Status.Should().Be(410);
        descriptor.Recoverable.Should().BeTrue();
        descriptor.Endpoints.Should().Equal(new ProblemEndpoint("POST", "/app-handoff/redeem"));
        JsonSerializer.Serialize(new AppHandoffExpired()).Should().Be("{}");

        FluentActions.Invoking(() => AuthEngineProblemCatalogExtensions.AddAtomiAuthEngineProblems(null!, config))
            .Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => new ProblemCatalogBuilder().AddAtomiAuthEngineProblems(null!))
            .Should().Throw<ArgumentNullException>();
    }

    private static DefaultHttpContext JsonContext(string body, string contentType = "application/json")
    {
        var context = new DefaultHttpContext();
        context.Request.ContentType = contentType;
        context.Request.Body = new MemoryStream(Encoding.UTF8.GetBytes(body));
        return context;
    }

    private static string Token(TestTokenIssuer issuer, AuthEngineConfig config, bool includeEmail) =>
        issuer.MintValidFor(
            AuthEngineFixture.Subject,
            config.Logto.Issuer,
            AuthEngineFixture.Now,
            TimeSpan.FromMinutes(10),
            extraClaims: includeEmail
                ? new Dictionary<string, object> { ["email"] = "owner@example.invalid" }
                : null);

    private sealed class StubMinter : IDeferredTokenMinter
    {
        internal Result<DeferredHandoff, IDomainProblem> MintOutcome { get; init; } =
            Result.Ok<DeferredHandoff, IDomainProblem>(
                new DeferredHandoff("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", AuthEngineFixture.Now));

        internal Result<DeferredExchange, IDomainProblem> ExchangeOutcome { get; init; } =
            Result.Err<DeferredExchange, IDomainProblem>(new AppHandoffExpired());

        internal List<string> Exchanged { get; } = [];

        public Task<Result<DeferredHandoff, IDomainProblem>> Mint(
            DeferredPayload payload,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(this.MintOutcome);

        public Task<Result<DeferredExchange, IDomainProblem>> Exchange(
            string token,
            CancellationToken cancellationToken = default)
        {
            this.Exchanged.Add(token);
            return Task.FromResult(this.ExchangeOutcome);
        }
    }
}
