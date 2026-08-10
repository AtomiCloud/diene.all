using AtomiCloud.Diene.ApiEngine.Client;
using AtomiCloud.Diene.ApiEngine.Config;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.DotnetBase.UnitTest;

/// <summary>
/// The values every suite in this project shares: one error portal, one upstream address, and a
/// configuration builder that does not repeat the same seven fields per test.
/// </summary>
internal static class ApiEngineFixture
{
    /// <summary>The error-portal identity the type URIs under test are built from.</summary>
    internal static readonly ProblemIdentity Identity = new("lapras", "lithium", "notes", "note");

    /// <summary>A type URI builder over <see cref="Identity" />.</summary>
    internal static IProblemTypeUriBuilder TypeUris { get; } =
        new ProblemTypeUriBuilder(new ErrorPortalConfig("https", "errors.test.invalid", Identity));

    /// <summary>The primary upstream under test.</summary>
    internal static ServiceAddress Notes { get; } = ServiceAddress.Create("lithium", "notes", "note").Get();

    /// <summary>A second upstream, for the per-backend isolation cases.</summary>
    internal static ServiceAddress Archive { get; } = ServiceAddress.Create("lithium", "notes", "archive").Get();

    /// <summary>The base address the fixtures configure.</summary>
    internal const string BaseAddress = "https://notes.test.invalid/";

    /// <summary>Builds one option entry, defaulting everything a test does not care about.</summary>
    internal static HttpClientOption Option(
        string? baseAddress = BaseAddress,
        string timeout = "PT30S",
        string? authResource = null,
        bool rescueRoutingEnabled = false,
        params string[] scopes)
    {
        var option = new HttpClientOption
        {
            BaseAddress = baseAddress!,
            Timeout = timeout,
            AuthResource = authResource,
            RescueRoutingEnabled = rescueRoutingEnabled,
        };
        foreach (var scope in scopes) option.AuthScopes.Add(scope);
        return option;
    }

    /// <summary>Builds a validated single-upstream configuration.</summary>
    internal static ApiEngineConfig Config(
        ServiceAddress? address = null,
        string? authResource = null,
        bool rescueRoutingEnabled = false) =>
        ApiEngineConfig.Create(new Dictionary<string, HttpClientOption>(StringComparer.Ordinal)
        {
            [(address ?? Notes).ToString()] = Option(
                authResource: authResource,
                rescueRoutingEnabled: rescueRoutingEnabled),
        }).Get();

    /// <summary>The type URI a problem id resolves to under <see cref="Identity" />.</summary>
    internal static string TypeUri(string version, string id) => TypeUris.Build(version, id).AbsoluteUri;
}
