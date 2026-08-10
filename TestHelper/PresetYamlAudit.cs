using AtomiCloud.Diene.StandardConfig.Presets;
using FluentAssertions;
using YamlDotNet.RepresentationModel;

namespace AtomiCloud.Diene.StandardConfig.TestHelper;

/// <summary>One connection name that broke the UPPERCASE contract, and where.</summary>
public sealed record PresetKeyViolation(string File, string Block, string Name)
{
    /// <inheritdoc />
    public override string ToString() => $"{File}: {Block}.{Name} is not UPPERCASE";
}

/// <summary>
/// Audits config YAML for the R14 UPPERCASE connection-pool-name contract.
/// </summary>
/// <remarks>
/// <para>
/// This exists because the contract cannot be enforced anywhere else on .NET. The config
/// lib reduces every key segment through the canonical rule before the binder runs, so a
/// bound block cannot tell <c>MAIN</c> from <c>main</c> — see <see cref="PresetKey" />. The
/// SOURCE still can, and the source is what an author actually edits.
/// </para>
/// <para>
/// Wire it into a consumer's own test suite over the service's <c>settings*.yaml</c> files.
/// It reads YAML rather than loading config: it is a lint on authored text, not a config
/// layer, and standard-config remains a library that never loads anything.
/// </para>
/// </remarks>
public static class PresetYamlAudit
{
    /// <summary>The preset block names this audit inspects.</summary>
    public static readonly IReadOnlyList<string> BlockNames =
        [PostgresOption.Key, CacheOption.Key, KvOption.Key, StorageOption.Key];

    /// <summary>Every violation in one YAML file.</summary>
    public static IReadOnlyList<PresetKeyViolation> Audit(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        using var reader = new StreamReader(path);
        return Audit(Path.GetFileName(path), reader);
    }

    /// <summary>Every violation in one YAML document read from <paramref name="reader" />.</summary>
    public static IReadOnlyList<PresetKeyViolation> Audit(string label, TextReader reader)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(label);
        ArgumentNullException.ThrowIfNull(reader);

        var stream = new YamlStream();
        stream.Load(reader);

        if (stream.Documents.Count == 0) return [];
        if (stream.Documents[0].RootNode is not YamlMappingNode root) return [];

        var violations = new List<PresetKeyViolation>();

        foreach (var (blockKey, blockNode) in root.Children)
        {
            if (blockKey is not YamlScalarNode { Value: { } blockName }) continue;
            if (!BlockNames.Any(known => KeysMatch(known, blockName))) continue;
            if (blockNode is not YamlMappingNode connections) continue;

            foreach (var (nameKey, _) in connections.Children)
            {
                if (nameKey is not YamlScalarNode { Value: { } name }) continue;
                if (PresetKey.IsValid(name)) continue;
                violations.Add(new PresetKeyViolation(label, blockName, name));
            }
        }

        return violations;
    }

    /// <summary>Asserts a YAML file names every connection in UPPERCASE.</summary>
    public static void ShouldUseUppercaseConnectionNames(string path) =>
        Audit(path).Should().BeEmpty(
            "R14 requires UPPERCASE connection-pool names, and .NET's canonical key rule means " +
            "the source file is the only place that can still be checked");

    /// <summary>Asserts every matching YAML file in a directory names its connections in UPPERCASE.</summary>
    public static void ShouldUseUppercaseConnectionNames(string directory, string searchPattern)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        ArgumentException.ThrowIfNullOrWhiteSpace(searchPattern);

        var violations = Directory
            .EnumerateFiles(directory, searchPattern, SearchOption.AllDirectories)
            .Order(StringComparer.Ordinal)
            .SelectMany(Audit)
            .ToArray();

        violations.Should().BeEmpty("R14 requires UPPERCASE connection-pool names in every config layer");
    }

    /// <summary>
    /// Block names are matched the way the config lib matches them, so a block authored as
    /// <c>error_portal</c>-style snake case is still recognised as its Pascal-cased key.
    /// </summary>
    private static bool KeysMatch(string a, string b) => AtomiCloud.Diene.CoreUtils.KeyNormalizer.KeysMatch(a, b);
}
