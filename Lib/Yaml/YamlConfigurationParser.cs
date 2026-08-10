using Microsoft.Extensions.Configuration;
using YamlDotNet.RepresentationModel;

namespace AtomiCloud.Diene.Config.Yaml;

/// <summary>
/// Flattens one YAML document into the flat, canonically-keyed dictionary the
/// configuration stack layers.
/// </summary>
internal static class YamlConfigurationParser
{
    /// <summary>
    /// The generated schema pointer C0 requires as the first line of every config YAML.
    /// It addresses the document, not the service, so it never becomes a config key.
    /// </summary>
    private const string SchemaPointerKey = "$schema";

    internal static IDictionary<string, string?> Parse(Stream stream)
    {
        ArgumentNullException.ThrowIfNull(stream);

        var data = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        var yaml = new YamlStream();
        using var reader = new StreamReader(stream);
        yaml.Load(reader);

        // An empty document is a legal, empty layer.
        if (yaml.Documents.Count == 0) return data;

        var root = yaml.Documents[0].RootNode;

        // A document holding only comments parses to an empty scalar, not a mapping.
        if (root is YamlScalarNode { Value: null or "" }) return data;

        if (root is not YamlMappingNode mapping)
            throw new InvalidDataException(
                $"A config layer must be a YAML mapping at its root, but this one is {root.NodeType}.");

        foreach (var (key, value) in mapping.Children)
        {
            var name = Scalar(key);
            if (string.Equals(name, SchemaPointerKey, StringComparison.Ordinal)) continue;
            Visit(data, ConfigKey.Segment(name), value);
        }

        return data;
    }

    private static void Visit(IDictionary<string, string?> data, string path, YamlNode node)
    {
        if (node is YamlMappingNode mapping)
        {
            foreach (var (key, value) in mapping.Children)
                Visit(data, Join(path, ConfigKey.Segment(Scalar(key))), value);
            return;
        }

        // Sequences become indexed keys, matching the indexed-key list encoding the env layer
        // uses (FOO__0, FOO__1, …), so a list is overridable element by element.
        if (node is YamlSequenceNode sequence)
        {
            for (var index = 0; index < sequence.Children.Count; index++)
                Visit(
                    data,
                    Join(path, index.ToString(System.Globalization.CultureInfo.InvariantCulture)),
                    sequence.Children[index]);
            return;
        }

        // Everything else is a scalar: the representation model resolves anchors and aliases
        // to the node they name, so mapping, sequence, and scalar are the only kinds a parsed
        // document contains. A blank scalar is the secrets convention — the key is declared
        // here and its value arrives from the environment layer, so it must still occupy the key.
        data[path] = ((YamlScalarNode)node).Value;
    }

    private static string Join(string path, string segment) => path + ConfigurationPath.KeyDelimiter + segment;

    private static string Scalar(YamlNode node) => node is YamlScalarNode { Value: { } value }
        ? value
        : throw new InvalidDataException($"Config keys must be YAML scalars, but one is {node.NodeType}.");
}
