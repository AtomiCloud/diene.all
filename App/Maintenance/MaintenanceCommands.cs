using AtomiCloud.Diene.Config;
using AtomiCloud.Diene.Problems;
using AtomiCloud.DotnetBase.App.Error;
using AtomiCloud.DotnetBase.App.StartUp.Registration;

namespace AtomiCloud.DotnetBase.App.Maintenance;

/// <summary>
/// Dev and CI maintenance commands. These are deliberately NOT run modes: a deployment only
/// ever runs <c>server</c> or <c>db-init</c>. Schema generation and catalog export are build-time
/// concerns, and nothing here is reachable from a serving process.
/// </summary>
public static class MaintenanceCommands
{
    /// <summary>Writes the generated configuration schema.</summary>
    public const string ConfigSchemaWrite = "config:schema";

    /// <summary>Fails when the generated configuration schema has drifted from the options types.</summary>
    public const string ConfigSchemaVerify = "config:schema:verify";

    /// <summary>
    /// Binds and validates every registered configuration block against the FINAL merged layer
    /// and reports the result. This is the fail-fast that <c>ValidateOnStart</c> performs at
    /// boot, invoked on its own so it can be gated without starting a web host.
    /// </summary>
    public const string ConfigValidate = "config:validate";

    /// <summary>Writes the Problem catalog resource for the primordial chart.</summary>
    public const string ProblemsExport = "problems:export";

    /// <summary>Fails when the exported Problem catalog has drifted from the registered catalog.</summary>
    public const string ProblemsVerify = "problems:verify";

    /// <summary>
    /// Where the generated configuration schema lives, beside the config it describes.
    /// Repository-relative — see <see cref="Absolute"/> for why that needs resolving.
    /// </summary>
    public const string SchemaPath = "App/Config/settings.schema.json";

    /// <summary>
    /// Where the exported Problem catalog lands for the primordial chart to bundle. One resource
    /// per problem VERSION, because that is the row the emitter models.
    /// </summary>
    public const string CatalogDirectory = "infra/primordial_chart/problems";

    /// <summary>Filename pattern for an exported catalog, keyed on the problem version.</summary>
    public const string CatalogPattern = "catalog-{0}.json";

    /// <summary>The file that marks the repository root.</summary>
    public const string RootMarker = "dotnet-base.slnx";

    /// <summary>Exit code for a successful command.</summary>
    public const int Success = 0;

    /// <summary>Exit code for drift or a failed write.</summary>
    public const int Failure = 1;

    /// <summary>Every verb this dispatcher answers to.</summary>
    public static IReadOnlySet<string> Verbs { get; } = new HashSet<string>(StringComparer.Ordinal)
    {
        ConfigSchemaWrite,
        ConfigSchemaVerify,
        ConfigValidate,
        ProblemsExport,
        ProblemsVerify,
    };

    /// <summary>Runs a maintenance verb.</summary>
    /// <param name="verb">One of <see cref="Verbs"/>.</param>
    /// <returns>The process exit code.</returns>
    public static Task<int> RunAsync(string verb) => Task.FromResult(verb switch
    {
        ConfigSchemaWrite => WriteConfigSchema(),
        ConfigSchemaVerify => VerifyConfigSchema(),
        ConfigValidate => ValidateConfig(),
        ProblemsExport => WriteProblemCatalog(),
        ProblemsVerify => VerifyProblemCatalog(),
        _ => throw new ArgumentOutOfRangeException(nameof(verb), verb, "not a maintenance verb"),
    });

    private static int WriteConfigSchema() => ConfigSchemaGen
        .WriteSchema(ConfigurationRegistration.SchemaRegistry(), Absolute(SchemaPath))
        .Match(
            _ =>
            {
                Console.WriteLine($"wrote configuration schema to {SchemaPath}");
                return Success;
            },
            error => Report($"could not write {SchemaPath}", error.ToString()));

    private static int VerifyConfigSchema() => ConfigSchemaGen
        .VerifySchema(ConfigurationRegistration.SchemaRegistry(), Absolute(SchemaPath))
        .Match(
            _ =>
            {
                Console.WriteLine($"configuration schema at {SchemaPath} matches the options types");
                return Success;
            },
            error => Report($"configuration schema drift at {SchemaPath}", $"{error.Fault}: {error.Detail}"));

    private static int ValidateConfig()
    {
        var builder = Host.CreateApplicationBuilder();
        builder.Configuration.AddServiceConfiguration(landscape: string.Empty);
        builder.Services.AddServiceOptions();

        // Each Resolve binds its block against the final merged layer and runs its validator,
        // which is exactly what ValidateOnStart does at boot. Resolving them one at a time
        // means the failure NAMES the offending block instead of reporting "configuration".
        var blocks = new (string Name, Func<object> Bind)[]
        {
            (AppOption.Key, () => builder.Services.Resolve<AppOption>()),
            (ErrorPortalOption.Key, () => builder.Services.Resolve<ErrorPortalOption>()),
            (AtomiCloud.Diene.Otel.OtelOption.Key, () => builder.Services.Resolve<AtomiCloud.Diene.Otel.OtelOption>()),
            (Options.ServerOption.Key, () => builder.Services.Resolve<Options.ServerOption>()),
            (Options.AuthOption.Key, () => builder.Services.Resolve<Options.AuthOption>()),
            (Options.HttpOption.Key, () => builder.Services.Resolve<Options.HttpOption>()),
            (Options.DbInitOption.Key, () => builder.Services.Resolve<Options.DbInitOption>()),
            (AtomiCloud.Diene.StandardConfig.Presets.PostgresOption.Key, () => builder.Services.Resolve<AtomiCloud.Diene.StandardConfig.Presets.PostgresBlock>()),
            (AtomiCloud.Diene.StandardConfig.Presets.CacheOption.Key, () => builder.Services.Resolve<AtomiCloud.Diene.StandardConfig.Presets.CacheBlock>()),
            (AtomiCloud.Diene.StandardConfig.Presets.KvOption.Key, () => builder.Services.Resolve<AtomiCloud.Diene.StandardConfig.Presets.KvBlock>()),
            (AtomiCloud.Diene.StandardConfig.Presets.StorageOption.Key, () => builder.Services.Resolve<AtomiCloud.Diene.StandardConfig.Presets.StorageBlock>()),
        };

        var failures = 0;
        foreach (var (name, bind) in blocks)
        {
            try
            {
                bind();
                Console.WriteLine($"   ok      {name}");
            }
            catch (Exception failure)
            {
                Console.Error.WriteLine($"   INVALID {name}: {failure.Message}");
                failures++;
            }
        }

        Console.WriteLine(
            $"config:validate: {blocks.Length} block(s) checked, {blocks.Length - failures} valid, {failures} invalid");

        if (failures == 0) return Success;

        Console.Error.WriteLine($"configuration is invalid on the final merged layer: {failures} block(s)");
        return Failure;
    }

    private static int WriteProblemCatalog()
    {
        var exported = Exports();
        var directory = Absolute(CatalogDirectory);
        Directory.CreateDirectory(directory);

        foreach (var (version, serialized) in exported)
            File.WriteAllText(Path.Combine(directory, Filename(version)), serialized);

        // A version dropped from the catalog must lose its file too, or the chart keeps
        // shipping a resource the service no longer declares.
        var orphans = Orphans(directory, exported.Keys);
        foreach (var orphan in orphans) File.Delete(orphan);

        Console.WriteLine(
            $"wrote {exported.Count} catalog resource(s) to {CatalogDirectory}: " +
            $"{string.Join(", ", exported.Keys)}; removed {orphans.Count} orphan(s)");
        return Success;
    }

    private static int VerifyProblemCatalog()
    {
        var exported = Exports();
        var directory = Absolute(CatalogDirectory);

        if (exported.Count == 0)
            return Report(CatalogDirectory, "the registered catalog declares no problems at all");

        if (!Directory.Exists(directory))
            return Report(CatalogDirectory, "the export directory does not exist; run problems:export");

        var drifted = new List<string>();
        foreach (var (version, serialized) in exported)
        {
            var path = Path.Combine(directory, Filename(version));
            if (!File.Exists(path)) drifted.Add($"{Filename(version)} missing");
            else if (!SameCatalog(File.ReadAllText(path), serialized))
                drifted.Add($"{Filename(version)} differs from the registered catalog");
        }

        foreach (var orphan in Orphans(directory, exported.Keys))
            drifted.Add($"{Path.GetFileName(orphan)} has no matching problem version");

        if (drifted.Count > 0)
            return Report(CatalogDirectory, $"{drifted.Count} drift(s): {string.Join("; ", drifted)}; run problems:export");

        Console.WriteLine(
            $"{exported.Count} catalog resource(s) in {CatalogDirectory} match the registered catalog: " +
            $"{string.Join(", ", exported.Keys)}");
        return Success;
    }

    /// <summary>
    /// Serializes one Problem resource per DISTINCT problem version in the registered catalog.
    /// </summary>
    /// <remarks>
    /// The <c>Version</c> on <c>ProblemResourceIdentity</c> is the PROBLEM version (`v1`), not
    /// the application version. Passing the app version made the emitter throw
    /// "Problem catalog does not contain requested version" — the row it models is
    /// platform/service/landscape/PROBLEM-VERSION.
    /// </remarks>
    private static SortedDictionary<string, string> Exports() => Compose((catalog, emitter, app) =>
    {
        var byVersion = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var version in catalog.All.Select(descriptor => descriptor.Version).Distinct())
        {
            byVersion[version] = emitter.Serialize(emitter.Emit(
                new ProblemResourceIdentity(app.Platform, app.Service, app.Landscape, version)));
        }

        return byVersion;
    });

    /// <summary>
    /// Compares two catalog documents by CONTENT, not by bytes.
    /// </summary>
    /// <remarks>
    /// A byte comparison would put this gate in a fight it cannot win: treefmt owns formatting
    /// for every tracked file and reformats the emitted JSON, after which a byte-equal check
    /// reports catalog drift that does not exist. Two gates that redden each other conceal
    /// whichever one is telling the truth. Formatting belongs to treefmt; this gate owns
    /// whether the exported catalog still describes the registered one.
    /// A document that will not parse is drift, not a pass.
    /// </remarks>
    private static bool SameCatalog(string actual, string expected)
    {
        try
        {
            return System.Text.Json.Nodes.JsonNode.DeepEquals(
                System.Text.Json.Nodes.JsonNode.Parse(actual),
                System.Text.Json.Nodes.JsonNode.Parse(expected));
        }
        catch (System.Text.Json.JsonException)
        {
            return false;
        }
    }

    private static string Filename(string version) =>
        string.Format(System.Globalization.CultureInfo.InvariantCulture, CatalogPattern, version);

    private static IReadOnlyList<string> Orphans(string directory, IEnumerable<string> versions)
    {
        var expected = versions.Select(Filename).ToHashSet(StringComparer.Ordinal);
        return [.. Directory
            .EnumerateFiles(directory, string.Format(System.Globalization.CultureInfo.InvariantCulture, CatalogPattern, "*"))
            .Where(path => !expected.Contains(Path.GetFileName(path)))
            .Order(StringComparer.Ordinal)];
    }

    /// <summary>
    /// Builds the minimum host these commands need: the configuration layers and the problem
    /// catalog. It deliberately does NOT compose the web host — a build-time command must not
    /// need a database, a cache, or a collector to run.
    /// </summary>
    private static T Compose<T>(Func<IProblemCatalog, ProblemResourceEmitter, AppOption, T> use)
    {
        var builder = Host.CreateApplicationBuilder();

        builder.Configuration.AddServiceConfiguration(landscape: string.Empty);
        builder.Services.AddServiceOptions();

        var app = builder.Services.Resolve<AppOption>();
        var portal = builder.Services.Resolve<ErrorPortalOption>();

        builder.Services.AddAtomiProblems(
            new ProblemIdentity(app.Landscape, app.Platform, app.Service, app.Module),
            portal,
            catalog => catalog.AddServiceProblems());

        using var host = builder.Build();
        return use(
            host.Services.GetRequiredService<IProblemCatalog>(),
            host.Services.GetRequiredService<ProblemResourceEmitter>(),
            app);
    }

    /// <summary>
    /// Resolves a repository-relative path against the repository ROOT rather than the process
    /// working directory.
    /// </summary>
    /// <remarks>
    /// This is not defensive plumbing; it fixes a real defect. <c>dotnet run --project</c> sets
    /// the working directory to the PROJECT directory, so <c>App/Config/settings.schema.json</c>
    /// resolved to <c>App/App/Config/settings.schema.json</c> and the command reported success
    /// while writing to a path nothing reads. The serving host is unaffected because it reads
    /// <c>Config/settings.yaml</c>, which is correct relative to the project directory AND to
    /// the container's WORKDIR — but a build-time command writing repository artifacts needs
    /// the root.
    /// </remarks>
    /// <param name="relative">A repository-relative path.</param>
    /// <returns>An absolute path.</returns>
    public static string Absolute(string relative)
    {
        var directory = new DirectoryInfo(Environment.CurrentDirectory);

        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, RootMarker)))
                return Path.Combine(directory.FullName, relative);
            directory = directory.Parent;
        }

        throw new InvalidOperationException(
            $"could not find the repository root: no '{RootMarker}' at or above '{Environment.CurrentDirectory}'");
    }

    private static int Report(string what, string detail)
    {
        Console.Error.WriteLine($"{what}: {detail}");
        return Failure;
    }
}
