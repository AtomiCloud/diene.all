using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Onboarding;
using AtomiCloud.Diene.ServerEngine.Module;
using AtomiCloud.Diene.ServerEngine.Mvc;
using AtomiCloud.Diene.ServerEngine.Onboarding;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using CoreUtils = AtomiCloud.Diene.CoreUtils;

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
    private static readonly JsonSerializerOptions Wire = BuildWireOptions();

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
        var authConfig = auth.Get();
        using var tokens = new DemoTokens();
        await using var app = ServerEngineDemo.BuildApp(config, authConfig, tokens);

        await app.StartAsync().ConfigureAwait(false);

        var handler = app.Services.GetServices<IWebhookHandler>().OfType<DemoWebhookHandler>().Single();
        var backend = (DemoOnboardingBackend)app.Services.GetRequiredService<IOnboardingBackend>();

        Console.WriteLine(ServerEngineDemo.DescribeControllers());
        Console.WriteLine(ServerEngineDemo.DescribeWebhookWindow(config));
        Console.WriteLine(
            ServerEngineDemo.DescribeProviders(app.Services.GetRequiredService<WebhookHandlerRegistry>()));

        using var client = new HttpClient { BaseAddress = new Uri(ResolveAddress(app), UriKind.Absolute) };
        var failures = await WalkAsync(client, handler).ConfigureAwait(false);
        failures += await WalkOnboardSyncAsync(client, tokens, authConfig, backend).ConfigureAwait(false);

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

        // The demo READS what it fetches rather than only checking a status. A walk that only
        // looked at status codes would pass against a service serializing an empty object.
        var version = await client.GetFromJsonAsync<SystemVersionView>("/system/version", Wire).ConfigureAwait(false);
        Console.WriteLine(
            $"identity: {version!.Landscape}/{version.Platform}/{version.Service}/{version.Module} " +
            $"at {version.Version}");

        var health = await client.GetFromJsonAsync<SystemHealthView>("/system/health", Wire).ConfigureAwait(false);
        Console.WriteLine($"health: {health!.Status} at {CoreUtils.Wire.Format(health.CheckedAt)}");

        var note = await client.GetFromJsonAsync<DemoNote>("/notes/note-1", Wire).ConfigureAwait(false);
        Console.WriteLine($"note: {note!.Id} titled '{note.Title}'");

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

    /// <summary>
    /// Drives the whole OnboardSync machine with real signed tokens: an un-onboarded caller is
    /// shown the selector, the pick is written, and a caller carrying the claim is complete.
    /// </summary>
    public static async Task<int> WalkOnboardSyncAsync(
        HttpClient client,
        DemoTokens tokens,
        AuthEngineConfig auth,
        DemoOnboardingBackend backend)
    {
        ArgumentNullException.ThrowIfNull(client);
        ArgumentNullException.ThrowIfNull(tokens);
        ArgumentNullException.ThrowIfNull(auth);
        ArgumentNullException.ThrowIfNull(backend);

        const string subject = "demo-user";
        var now = DateTimeOffset.UtcNow;
        var issuer = auth.Logto.Issuer;
        var claim = auth.HomeLandscapeClaim;
        var failures = 0;

        var fresh = tokens.Mint(subject, issuer, now, null, claim);
        var before = await ReadPhaseAsync(client, fresh).ConfigureAwait(false);
        Console.WriteLine($"onboarding phase before the pick: {before}");
        if (before != OnboardingPhase.SelectLandscape) failures++;

        using var pick = new HttpRequestMessage(HttpMethod.Post, "/internal/onboard-sync/complete")
        {
            Content = JsonContent.Create(new OnboardSyncCompleteRequest(ServerEngineDemo.DemoLandscape), options: Wire),
        };
        pick.Headers.Authorization = new AuthenticationHeaderValue("Bearer", fresh);
        using var picked = await client.SendAsync(pick).ConfigureAwait(false);
        Console.WriteLine($"POST /internal/onboard-sync/complete -> {(int)picked.StatusCode}");
        if (picked.StatusCode != HttpStatusCode.NoContent) failures++;

        var synced = await ReadPhaseAsync(client, fresh).ConfigureAwait(false);
        Console.WriteLine($"onboarding phase after the pick: {synced}");
        if (synced != OnboardingPhase.AwaitingSync) failures++;

        var onboarded = tokens.Mint(subject, issuer, now, ServerEngineDemo.DemoLandscape, claim);
        var complete = await ReadPhaseAsync(client, onboarded).ConfigureAwait(false);
        Console.WriteLine($"onboarding phase with the claim present: {complete}");
        if (complete != OnboardingPhase.Complete) failures++;

        Console.WriteLine($"home landscapes written: {string.Join(", ", backend.Written.Select(w => $"{w.Key}={w.Value}"))}");
        return failures;
    }

    private static async Task<OnboardingPhase> ReadPhaseAsync(HttpClient client, string token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/internal/onboard-sync/phase");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        using var response = await client.SendAsync(request).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        var view = await response.Content.ReadFromJsonAsync<OnboardSyncPhaseView>(Wire).ConfigureAwait(false);
        return view!.Phase;
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

    /// <summary>
    /// The client reads with the same published contract the server writes with, so the demo
    /// proves the round trip instead of re-implementing half of it.
    /// </summary>
    private static JsonSerializerOptions BuildWireOptions()
    {
        var options = new JsonSerializerOptions();
        ServerEngineServiceCollectionExtensions.ApplyWireContract(options);
        return options;
    }

    private static string ResolveAddress(WebApplication app)
    {
        var addresses = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>();
        return addresses?.Addresses.FirstOrDefault() ??
               throw new InvalidOperationException("The demo host did not report a bound address.");
    }
}
