using AtomiCloud.Diene.Config;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// Walks the whole config contract end to end and reports what each step proved, so the
/// behaviour is observable from a terminal and not only from the test suite.
/// </summary>
public static class Demo
{
    /// <summary>A deployment's worth of injected environment.</summary>
    private static readonly KeyValuePair<string, string?>[] Injected =
    [
        // Snake-cased env name against a snake-cased YAML key against a Pascal property: all
        // three are the same key once canonicalized.
        new("ATOMI_ERROR_PORTAL__SIGNING_KEY", "injected-by-the-landscape"),

        // A list overridden element-wise through indexed keys. No JSON, no commas.
        new("ATOMI_ERROR_PORTAL__RETRY_HOSTS__0", "docs-fallback.atomi.cloud"),

        // Not ours: a variable without the configured prefix contributes nothing.
        new("PATH_TO_NOWHERE", "ignored"),
    ];

    /// <summary>Runs every step and returns the lines to print.</summary>
    public static IReadOnlyList<string> Run()
    {
        var lines = new List<string>();

        // ── layering: base → sparse landscape overlay → environment LAST ──
        // Built the way a deployed service builds it, off the real process environment.
        var configuration = WithInjectedEnvironment(() => ConfigComposition.Build("lapras"));

        lines.Add($"base default kept:      error_portal.scheme = {configuration[ConfigKey.Path("ErrorPortal:Scheme")]}");
        lines.Add($"landscape overrode base: error_portal.host   = {configuration[ConfigKey.Path("error_portal:host")]}");
        lines.Add($"env overrode both:      error_portal.signing_key = {configuration["errorportal:signingkey"]}");
        lines.Add($"indexed list element 0: {configuration["errorportal:retryhosts:0"]}");
        lines.Add($"indexed list element 1: {configuration["errorportal:retryhosts:1"]}");
        lines.Add($"canonical key rule:     '{ConfigKey.Segment("error_portal")}' from error_portal, error-portal, errorPortal");
        lines.Add($"landscape variable:     {AtomiConfigSource.LandscapeVariable}");

        // ── binding + fail-fast validation on the FINAL merged layer ──
        using var provider = ConfigComposition.Provider(configuration);
        var app = provider.GetRequiredService<IOptions<AppOption>>().Value;
        var portal = provider.GetRequiredService<IOptions<ErrorPortalOption>>().Value;

        lines.Add($"service tree bound:     {app.Landscape}/{app.Platform}/{app.Service}/{app.Module}@{app.Version}");
        lines.Add($"portal bound:           {portal.Scheme}://{portal.Host} via {string.Join(", ", portal.RetryHosts)}");

        // A validator is an ordinary object: consumers can run it directly, with no host.
        var standalone = new ErrorPortalOptionValidator().Validate(new ErrorPortalOption());
        lines.Add($"validator standalone:   {standalone.Errors.Count} rule failures on an empty block");

        // ── fail-fast: the same stack refuses to start when the secret is not injected ──
        lines.Add($"fail-fast without secret: {FailFast()}");

        // ── generated schema: written by a task, verified in CI ──
        lines.AddRange(Schema());

        return lines;
    }

    /// <summary>Applies the injected environment for the duration of one build, then restores it.</summary>
    private static T WithInjectedEnvironment<T>(Func<T> build)
    {
        var previous = Injected
            .Select(entry => new KeyValuePair<string, string?>(entry.Key, Environment.GetEnvironmentVariable(entry.Key)))
            .ToArray();

        foreach (var (name, value) in Injected) Environment.SetEnvironmentVariable(name, value);
        try
        {
            return build();
        }
        finally
        {
            foreach (var (name, value) in previous) Environment.SetEnvironmentVariable(name, value);
        }
    }

    /// <summary>Proves the merged config is rejected at startup when the secret never arrives.</summary>
    private static string FailFast()
    {
        var configuration = ConfigComposition.Build("lapras", []);
        using var provider = ConfigComposition.Provider(configuration);
        try
        {
            _ = provider.GetRequiredService<IOptions<ErrorPortalOption>>().Value;
            return "NOT REJECTED — this is a defect";
        }
        catch (OptionsValidationException exception)
        {
            return exception.Failures.First();
        }
    }

    /// <summary>Round-trips the generated schema through write and verify, including drift.</summary>
    private static IEnumerable<string> Schema()
    {
        var registry = ConfigComposition.Registry();
        var path = Path.Combine(Path.GetTempPath(), $"diene-config-demo-{Environment.ProcessId}", "settings.schema.json");

        var blocks = registry is ConfigSchemaRegistry concrete ? string.Join(", ", concrete.Blocks.Keys) : "";
        yield return $"schema blocks:          {blocks}";

        yield return ConfigSchemaGen.WriteSchema(registry, path)
            .Match(_ => $"schema written:         {Path.GetFileName(path)}", Describe);

        yield return ConfigSchemaGen.VerifySchema(registry, path)
            .Match(_ => "schema verified:        no drift", Describe);

        // Drift is what CI actually reds on, so the demo shows it rather than describing it.
        File.WriteAllText(path, "{}");
        yield return ConfigSchemaGen.VerifySchema(registry, path)
            .Match(_ => "drift NOT detected — this is a defect", Describe);

        var directory = Path.GetDirectoryName(path);
        if (directory is not null) Directory.Delete(directory, recursive: true);

        yield return ConfigSchemaGen.VerifySchema(registry, path).Match(_ => "missing NOT detected — this is a defect", Describe);
    }

    private static string Describe(SchemaGenError error) => $"schema {error.Fault}:{Pad(error.Fault)}{error.Detail}";

    private static string Pad(SchemaGenFault fault) => new(' ', Math.Max(1, 18 - fault.ToString().Length));
}
