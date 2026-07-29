using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Module;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Routing;

const string mount = "/surface-probe";
var management = LogtoManagementConfig.Create(
    "https://idp.test.invalid",
    "https://idp.test.invalid/api",
    "management-client",
    "management-secret").Get();
var logto = LogtoConfig.Create(
    "https://idp.test.invalid",
    "https://idp.test.invalid/oidc",
    "app",
    "app-secret",
    management).Get();
var config = AuthEngineConfig.Create(
    logto,
    HandoffConfig.Create(mount).Get(),
    TokenLifetimeConfig.Default,
    "home_landscape").Get();

using var app = WebApplication.CreateBuilder().Build();
app.MapAtomiAuthEngine(config);
var routes = ((IEndpointRouteBuilder)app).DataSources
    .SelectMany(source => source.Endpoints)
    .OfType<RouteEndpoint>()
    .Select(endpoint => endpoint.RoutePattern.RawText)
    .Where(pattern => pattern is not null)
    .Cast<string>()
    .ToArray();

// Positive-control the route reader before trusting any missing-route verdict.
if (!routes.Contains($"{mount}/session", StringComparer.Ordinal))
{
    Console.Error.WriteLine("route probe positive control failed: session route was not visible");
    return 40;
}

var expected = new[] { mount, $"{mount}/redeem", $"{mount}/session" };
if (!routes.SequenceEqual(expected, StringComparer.Ordinal))
{
    Console.Error.WriteLine($"mapped routes differ: [{string.Join(", ", routes)}]");
    return 41;
}

Console.WriteLine($"PASS\tMapAtomiAuthEngine(config)\t{string.Join("\t", routes)}");
return 0;
