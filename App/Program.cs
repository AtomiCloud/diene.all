using System.Globalization;
using System.Net;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace AtomiCloud.DotnetBase.App;

/// <summary>Composition root and demo consumer.</summary>
/// <remarks>
/// The demo starts the real host and drives it over real HTTP rather than calling the
/// controllers in process. For a SERVER library that distinction is the whole point: routing,
/// the filter's status code, the media-type gate, and the exact problem+json bytes only exist
/// once a request has crossed the pipeline.
/// </remarks>
public static class Program
{
    /// <summary>Runs the demo and returns a process exit code.</summary>
    public static async Task<int> Main(string[] args)
    {
        _ = args;

        var built = ServerEngineDemo.BuildConfig("1.0.0-demo");
        if (built.IsFailure(out var configError))
        {
            Console.WriteLine($"configuration rejected -> {configError}");
            return 1;
        }

        var auth = ServerEngineDemo.BuildAuthConfig();
        if (auth.IsFailure(out var authError))
        {
            Console.WriteLine($"auth configuration rejected -> {authError}");
            return 1;
        }

        var config = built.Get();
        var handler = new DemoWebhookHandler();
        await using var app = ServerEngineDemo.BuildApp(config, auth.Get(), handler);

        await app.StartAsync().ConfigureAwait(false);

        Console.WriteLine(ServerEngineDemo.DescribeControllers());
        Console.WriteLine(ServerEngineDemo.DescribeWebhookWindow(config));
        Console.WriteLine(
            ServerEngineDemo.DescribeProviders(app.Services.GetRequiredService<WebhookHandlerRegistry>()));

        using var client = new HttpClient { BaseAddress = new Uri(ResolveAddress(app), UriKind.Absolute) };
        var failures = await WalkAsync(client, handler).ConfigureAwait(false);

        await app.StopAsync().ConfigureAwait(false);

        Console.WriteLine(failures == 0 ? "demo complete" : $"demo saw {failures} unexpected response(s)");
        return failures == 0 ? 0 : 1;
    }

    /// <summary>
    /// Drives every shipped route and reports how many answered something other than the
    /// contract's status. Counting rather than throwing keeps the whole walk visible in one run.
    /// </summary>
    public static async Task<int> WalkAsync(HttpClient client, DemoWebhookHandler handler)
    {
        ArgumentNullException.ThrowIfNull(client);
        ArgumentNullException.ThrowIfNull(handler);

        var failures = 0;

        failures += await ExpectAsync(client, HttpMethod.Get, "/system/version", HttpStatusCode.OK)
            .ConfigureAwait(false);
        failures += await ExpectAsync(client, HttpMethod.Get, "/system/health", HttpStatusCode.OK)
            .ConfigureAwait(false);
        failures += await ExpectAsync(client, HttpMethod.Get, "/notes/note-1", HttpStatusCode.OK)
            .ConfigureAwait(false);
        failures += await ExpectAsync(client, HttpMethod.Get, "/notes/note-1/async", HttpStatusCode.OK)
            .ConfigureAwait(false);
        failures += await ExpectAsync(client, HttpMethod.Get, "/notes/trace", HttpStatusCode.OK)
            .ConfigureAwait(false);
        failures += await ExpectAsync(client, HttpMethod.Delete, "/notes/note-1", HttpStatusCode.NoContent)
            .ConfigureAwait(false);
        failures += await ExpectAsync(client, HttpMethod.Delete, "/notes/note-1/async", HttpStatusCode.NoContent)
            .ConfigureAwait(false);

        // The filter's own work: a registered problem becomes its catalog status, an
        // unregistered one becomes 500 with an about:blank type.
        failures += await ExpectAsync(client, HttpMethod.Get, "/notes/absent", HttpStatusCode.NotFound)
            .ConfigureAwait(false);
        failures += await ExpectAsync(
                client,
                HttpMethod.Get,
                "/notes/note-1/unregistered",
                HttpStatusCode.InternalServerError)
            .ConfigureAwait(false);

        // OnboardSync without a bearer token: an auth-engine problem rendered by this package's
        // filter, with no identity provider in the loop.
        failures += await ExpectAsync(
                client,
                HttpMethod.Get,
                "/internal/onboard-sync/phase",
                HttpStatusCode.Unauthorized)
            .ConfigureAwait(false);

        failures += await WalkWebhooksAsync(client).ConfigureAwait(false);
        Console.WriteLine($"last delivery: {handler.LastDescription}");
        Console.WriteLine($"idempotency keys seen: {handler.Seen.Count}");
        return failures;
    }

    private static async Task<int> WalkWebhooksAsync(HttpClient client)
    {
        var now = DateTimeOffset.UtcNow;
        var failures = 0;

        var accepted = DemoDelivery.Envelope(DemoWebhookHandler.DemoProvider, "evt-1", now, 1);
        failures += await SendAsync(
                client,
                DemoDelivery.Request(DemoWebhookHandler.DemoProvider, accepted, now),
                HttpStatusCode.OK)
            .ConfigureAwait(false);

        // The same delivery again: at-least-once means this must still be 200, and the handler's
        // own key set is what stops the work from happening twice.
        failures += await SendAsync(
                client,
                DemoDelivery.Request(DemoWebhookHandler.DemoProvider, accepted, now),
                HttpStatusCode.OK)
            .ConfigureAwait(false);

        var disowned = DemoDelivery.Envelope(
            DemoWebhookHandler.DemoProvider,
            DemoWebhookHandler.DisownedEventId,
            now,
            1);
        failures += await SendAsync(
                client,
                DemoDelivery.Request(DemoWebhookHandler.DemoProvider, disowned, now),
                (HttpStatusCode)WebhookProtocol.NotMineStatus)
            .ConfigureAwait(false);

        var unknown = DemoDelivery.Envelope("paypal", "evt-2", now, 1);
        failures += await SendAsync(
                client,
                DemoDelivery.Request("paypal", unknown, now),
                (HttpStatusCode)WebhookProtocol.NotMineStatus)
            .ConfigureAwait(false);

        failures += await SendAsync(
                client,
                DemoDelivery.Request(DemoWebhookHandler.DemoProvider, accepted, now, "wrong-secret"),
                HttpStatusCode.Unauthorized)
            .ConfigureAwait(false);

        failures += await SendAsync(
                client,
                DemoDelivery.Request(
                    DemoWebhookHandler.DemoProvider,
                    accepted,
                    now,
                    DemoDelivery.Secret,
                    "application/json"),
                HttpStatusCode.UnsupportedMediaType)
            .ConfigureAwait(false);

        return failures;
    }

    private static async Task<int> ExpectAsync(
        HttpClient client,
        HttpMethod method,
        string path,
        HttpStatusCode expected) =>
        await SendAsync(client, new HttpRequestMessage(method, path), expected).ConfigureAwait(false);

    private static async Task<int> SendAsync(
        HttpClient client,
        HttpRequestMessage request,
        HttpStatusCode expected)
    {
        using (request)
        {
            using var response = await client.SendAsync(request).ConfigureAwait(false);
            var verdict = response.StatusCode == expected ? "ok" : $"EXPECTED {(int)expected}";
            Console.WriteLine(
                string.Create(
                    CultureInfo.InvariantCulture,
                    $"{request.Method} {request.RequestUri} -> {(int)response.StatusCode} {verdict}"));
            return response.StatusCode == expected ? 0 : 1;
        }
    }

    private static string ResolveAddress(WebApplication app)
    {
        var addresses = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>();
        return addresses?.Addresses.FirstOrDefault() ??
               throw new InvalidOperationException("The demo host did not report a bound address.");
    }
}
