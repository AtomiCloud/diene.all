using System.Collections.Concurrent;
using System.Net;
using System.Net.Mime;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// A real HTTP upstream, hosted in-process on a loopback port, serving one endpoint per branch
/// of the classification matrix.
/// </summary>
/// <remarks>
/// A real socket rather than a message-handler double, deliberately. The engine's job is to make
/// sense of what HTTP actually does — a body that is not JSON, a status with no body, a
/// connection that never answers — and a handler double is a description of those conditions
/// written by the same person who wrote the code being checked. This is the only venue where
/// "no exception escapes" can be claimed about real transport.
/// </remarks>
public sealed class DemoUpstream : IAsyncDisposable
{
    /// <summary>The path serving a successful JSON payload.</summary>
    public const string OkPath = "/notes/ok";

    /// <summary>The path serving an RFC 9457 problem envelope.</summary>
    public const string ProblemPath = "/notes/problem";

    /// <summary>The path serving a problem envelope wrapped under a member.</summary>
    public const string NestedProblemPath = "/notes/wrapped";

    /// <summary>The path serving well-formed JSON that is not a problem.</summary>
    public const string LegacyPath = "/notes/legacy";

    /// <summary>The path serving a non-JSON failure body.</summary>
    public const string GarbagePath = "/notes/garbage";

    /// <summary>The path serving a bare status with no body.</summary>
    public const string SilentPath = "/notes/silent";

    /// <summary>The type URI the problem endpoint reports, so a passthrough can be asserted.</summary>
    public const string ProblemType = "https://errors.demo.invalid/docs/demo/lithium/notes/note/v1/note_missing";

    private readonly WebApplication _app;
    private readonly ConcurrentBag<string> _authorizations = [];

    private DemoUpstream(WebApplication app) => _app = app;

    /// <summary>Gets the base address the upstream is listening on.</summary>
    public Uri BaseAddress { get; private set; } = new("http://127.0.0.1/");

    /// <summary>Gets every <c>Authorization</c> header value the upstream received.</summary>
    public IReadOnlyCollection<string> Authorizations => _authorizations;

    /// <summary>Starts the upstream on an ephemeral loopback port.</summary>
    public static async Task<DemoUpstream> StartAsync()
    {
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.UseSetting("urls", "http://127.0.0.1:0");
        builder.Logging.ClearProviders();

        var app = builder.Build();
        var upstream = new DemoUpstream(app);

        app.Use(async (context, next) =>
        {
            var authorization = context.Request.Headers.Authorization.ToString();
            if (!string.IsNullOrEmpty(authorization)) upstream._authorizations.Add(authorization);
            await next(context).ConfigureAwait(false);
        });

        app.MapGet(OkPath, () => Results.Json(new NoteView("note-1", "A real payload")));

        app.MapGet(ProblemPath, () => Results.Content(
            Fixtures.Problem(ProblemType, "Note Missing", 404, "Note 'note-404' does not exist."),
            "application/problem+json",
            statusCode: (int)HttpStatusCode.NotFound));

        app.MapGet(NestedProblemPath, () => Results.Content(
            Fixtures.NestedProblem("error", ProblemType, "Note Missing", 404, "Wrapped by a gateway."),
            MediaTypeNames.Application.Json,
            statusCode: (int)HttpStatusCode.NotFound));

        app.MapGet(LegacyPath, () => Results.Content(
            Fixtures.NonProblemJson("note rejected by a service with another error contract", 4001),
            MediaTypeNames.Application.Json,
            statusCode: (int)HttpStatusCode.BadRequest));

        app.MapGet(GarbagePath, () => Results.Content(
            "<html><body>502 Bad Gateway</body></html>",
            MediaTypeNames.Text.Html,
            statusCode: (int)HttpStatusCode.BadGateway));

        app.MapGet(SilentPath, () => Results.StatusCode((int)HttpStatusCode.ServiceUnavailable));

        await app.StartAsync().ConfigureAwait(false);
        upstream.BaseAddress = new Uri(
            app.Urls.First(url => url.StartsWith("http://", StringComparison.Ordinal)),
            UriKind.Absolute);
        return upstream;
    }

    /// <inheritdoc />
    public async ValueTask DisposeAsync()
    {
        await _app.StopAsync().ConfigureAwait(false);
        await _app.DisposeAsync().ConfigureAwait(false);
    }
}
