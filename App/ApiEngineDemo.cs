using System.Text.Json;
using AtomiCloud.Diene.ApiEngine.Calls;
using AtomiCloud.Diene.ApiEngine.Client;
using AtomiCloud.Diene.ApiEngine.Config;
using AtomiCloud.Diene.ApiEngine.Module;
using AtomiCloud.Diene.ApiEngine.Transport;
using AtomiCloud.Diene.ApiEngine.Upstreams;
using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// Composition and call helpers for the demo, wiring the engine the way a service does.
/// </summary>
/// <remarks>
/// Every helper here is called by <see cref="Program" />. A demo that merely exposes methods
/// nobody runs is documentation with a compiler attached, and the strict dead-code pass — which
/// excludes test projects — is what makes that visible.
/// </remarks>
public static class ApiEngineDemo
{
    /// <summary>The primary upstream's address in the service tree.</summary>
    public static readonly ServiceAddress Notes = ServiceAddress.Create("lithium", "notes", "note").Get();

    /// <summary>A second upstream, present so per-backend auth is exercised rather than asserted.</summary>
    public static readonly ServiceAddress Archive = ServiceAddress.Create("lithium", "notes", "archive").Get();

    /// <summary>The auth resource bound to <see cref="Notes" />.</summary>
    public const string NotesResource = "https://notes.demo.invalid";

    /// <summary>The auth resource bound to <see cref="Archive" />.</summary>
    public const string ArchiveResource = "https://archive.demo.invalid";

    /// <summary>
    /// A third upstream pointed at a port nothing listens on, so the retry-once profile runs through
    /// the real pipeline instead of being described.
    /// </summary>
    public static readonly ServiceAddress Unreachable = ServiceAddress.Create("lithium", "notes", "void").Get();

    /// <summary>
    /// The address <see cref="Unreachable" /> is configured with. Port 1 on loopback is reserved and
    /// nothing binds it, so a connection is REFUSED promptly rather than hanging until a timeout —
    /// which is the opaque, status-free failure the retry profile is specified against.
    /// </summary>
    public const string UnreachableAddress = "http://127.0.0.1:1/";

    /// <summary>The error-portal identity the demo builds problem type URIs from.</summary>
    public static readonly ProblemIdentity Identity = new("demo", "lithium", "notes", "note");

    /// <summary>Builds the validated <c>HttpClient</c> block for two upstreams behind one base address.</summary>
    /// <remarks>
    /// Both upstreams point at the same demo server on purpose: the property being demonstrated is
    /// that each carries its OWN credential, and sharing a host is what makes a token leak between
    /// them observable instead of hidden behind different addresses.
    /// </remarks>
    public static Result<ApiEngineConfig, ApiConfigError> BuildConfig(Uri baseAddress)
    {
        ArgumentNullException.ThrowIfNull(baseAddress);

        var notes = new HttpClientOption
        {
            BaseAddress = baseAddress.AbsoluteUri,
            Timeout = "PT5S",
            AuthResource = NotesResource,
            RescueRoutingEnabled = true,
        };
        notes.AuthScopes.Add("notes:read");

        var archive = new HttpClientOption
        {
            BaseAddress = baseAddress.AbsoluteUri,
            Timeout = "PT5S",
            AuthResource = ArchiveResource,
        };
        archive.AuthScopes.Add("archive:read");

        var unreachable = new HttpClientOption
        {
            BaseAddress = UnreachableAddress,
            Timeout = "PT5S",
            RescueRoutingEnabled = true,
        };

        return ApiEngineConfig.Create(new Dictionary<string, HttpClientOption>(StringComparer.Ordinal)
        {
            [Notes.ToString()] = notes,
            [Archive.ToString()] = archive,
            [Unreachable.ToString()] = unreachable,
        });
    }

    /// <summary>
    /// Composes the engine over an in-memory credential client and the demo's error portal.
    /// </summary>
    /// <remarks>
    /// The credential client is a demo double defined in this project rather than the shipped
    /// TestHelper's, for the same reason the upstream's error documents are: a service does not
    /// take a test dependency in production, and the TestHelper's equivalents are exercised by the
    /// test projects.
    /// </remarks>
    public static ServiceProvider Compose(ApiEngineConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);

        var services = new ServiceCollection();
        services.AddSingleton<IProblemTypeUriBuilder>(
            new ProblemTypeUriBuilder(new ErrorPortalConfig("https", "errors.demo.invalid", Identity)));
        services.AddSingleton<ICredentialClient>(new DemoCredentialClient());
        services.AddSingleton<IAuthClock>(SystemAuthClock.Instance);
        services.AddSingleton(TokenLifetimeConfig.Default);
        services.AddSingleton<TokenCache>();

        // The return value is consumed rather than discarded, so the fluent surface this engine
        // advertises is one the demo actually uses.
        var registered = services.AddAtomiClientTree(config, tree =>
        {
            var built = tree
                .Register(Notes, http => new NotesClient(http))
                .Register(Archive, http => new NotesClient(http))
                .Register(Unreachable, http => new NotesClient(http));
            Console.WriteLine(
                $"client tree registered: {string.Join(", ", built.Registered.Select(address => address.ToString()))}");
        });
        Console.WriteLine($"container holds {registered.Count} registrations");

        return services.BuildServiceProvider();
    }

    /// <summary>
    /// Registers this engine's problems in a catalog and reports what a consumer's error portal
    /// would publish for them.
    /// </summary>
    /// <remarks>
    /// Run rather than described: the statuses and recoverability come from the same constants the
    /// classifier stamps on the wire, and printing them beside the catalog's own answers is what
    /// shows the two agree.
    /// </remarks>
    public static string DescribeCatalog()
    {
        var catalog = new ProblemCatalogBuilder().AddBaseline().AddApiEngineProblems().Build();

        return $"catalog holds {catalog.All.Count} problems; " +
               $"upstream_rejected -> {catalog.StatusOf(new UpstreamRejected())} " +
               $"(recoverable {catalog.Find("v1", "upstream_rejected").Get().Recoverable}), " +
               $"upstream_transport_failure -> {catalog.StatusOf(new UpstreamTransportFailure())} " +
               $"(recoverable {catalog.Find("v1", "upstream_transport_failure").Get().Recoverable})";
    }

    /// <summary>Calls one path through an upstream and renders the outcome.</summary>
    public static async Task<string> Describe(
        ServiceProvider services,
        ServiceAddress address,
        string path,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(services);

        var tree = services.GetRequiredService<IClientTree>();
        var caller = services.GetRequiredService<IApiCaller>();
        var client = tree.Get<NotesClient>(address);

        var outcome = await caller
            .Call(address, token => client.GetAsync(path, token), cancellationToken)
            .ConfigureAwait(false);

        return outcome.Match(
            note => $"{path} -> ok: {note.Id} '{note.Body}'",
            problem => $"{path} -> problem {problem.Status} {problem.Type}: {problem.Detail}{Rejection(problem)}");
    }

    /// <summary>
    /// Renders the upstream's own answer when the failure was a rejection, and nothing otherwise.
    /// </summary>
    /// <remarks>
    /// The whole point of carrying the body verbatim is that a caller can read it, so the demo reads
    /// it. A payload nobody decodes is a field nobody would notice going wrong.
    /// </remarks>
    private static string Rejection(Problem problem)
    {
        if (!problem.Type.EndsWith("/v1/upstream_rejected", StringComparison.Ordinal)) return string.Empty;

        var payload = problem.Data?.Deserialize<UpstreamRejected>(AtomiJson.DefaultOptions);
        if (payload is null) return string.Empty;

        return $" [{payload.Upstream} answered {payload.UpstreamStatus} " +
               $"as {payload.ContentType}: {payload.Body}]";
    }

    /// <summary>Calls a value-free operation and renders the outcome.</summary>
    public static async Task<string> DescribePing(
        ServiceProvider services,
        ServiceAddress address,
        string path,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(services);

        var tree = services.GetRequiredService<IClientTree>();
        var caller = services.GetRequiredService<IApiCaller>();
        var client = tree.Get<NotesClient>(address);

        var outcome = await caller
            .Call(address, token => client.PingAsync(path, token), cancellationToken)
            .ConfigureAwait(false);

        return outcome.Match(
            _ => $"{path} -> ok (no payload)",
            problem => $"{path} -> problem {problem.Status}: {problem.Detail}");
    }

    /// <summary>
    /// Calls the upstream nothing listens on, THROUGH the registered pipeline, so the retry-once
    /// profile and the attempt count are produced rather than described.
    /// </summary>
    /// <remarks>
    /// Renders the attempt count and the rescue flag, because those are the two properties of this
    /// profile a reader cannot verify from a status alone: exactly two attempts means one retry, and
    /// the flag shows the dormant trip point being reported rather than acted on.
    /// </remarks>
    public static async Task<string> DescribeUnreachable(
        ServiceProvider services,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(services);

        var tree = services.GetRequiredService<IClientTree>();
        var caller = services.GetRequiredService<IApiCaller>();
        var client = tree.Get<NotesClient>(Unreachable);

        var outcome = await caller
            .Call(Unreachable, token => client.GetAsync(DemoUpstream.OkPath, token), cancellationToken)
            .ConfigureAwait(false);

        return outcome.Match(
            note => $"unexpected success: {note.Id}",
            problem =>
            {
                var payload = problem.Data?.Deserialize<UpstreamTransportFailure>(AtomiJson.DefaultOptions);
                return $"unreachable -> problem {problem.Status} after {payload?.Attempts} " +
                       $"of at most {RetryOnceHandler.MaxAttempts} attempt(s), " +
                       $"rescuable {payload?.Rescuable}: {problem.Detail}";
            });
    }

    private sealed class DemoCredentialClient : ICredentialClient
    {
        public Task<Result<TokenResponse, IDomainProblem>> AcquireAsync(
            string resource,
            IReadOnlyList<string> scopes,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            _ = scopes;

            // The token names its resource so a leak between upstreams would be visible in the
            // header the demo prints, rather than hidden behind an indistinguishable constant.
            return Task.FromResult(Result.Ok<TokenResponse, IDomainProblem>(
                new TokenResponse($"demo-token-for-{resource}", DateTimeOffset.UtcNow.AddHours(1))));
        }

        public Task<Result<RefreshedTokens, IDomainProblem>> RefreshAsync(
            string refreshToken,
            string resource,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(Result.Ok<RefreshedTokens, IDomainProblem>(new RefreshedTokens(
                new TokenResponse($"demo-token-for-{resource}", DateTimeOffset.UtcNow.AddHours(1)),
                $"rotated-from-{refreshToken}")));
        }

        public Task<Result<Unit, IDomainProblem>> RevokeUserSessionsAsync(
            string userId,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            _ = userId;
            return Task.FromResult(Result.Ok<Unit, IDomainProblem>(new Unit()));
        }
    }
}
