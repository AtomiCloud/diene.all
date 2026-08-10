using System.Globalization;
using System.Reflection;
using AtomiCloud.Diene.Config;

namespace AtomiCloud.Diene.StandardConfig.TestHelper.Containers;

/// <summary>
/// Flattens a preset entry into the <c>:</c>-delimited configuration keys the .NET binder
/// reads.
/// </summary>
/// <remarks>
/// A test that wants a container's connection to arrive through the REAL config path — rather
/// than being handed to the code under test directly — needs the entry as configuration
/// values. Keys are run through the config lib's canonical normalizer, so the values land
/// exactly where a YAML layer or an env override would have put them.
/// </remarks>
public static class PresetConfiguration
{
    /// <summary>Flattens one named entry under <paramref name="blockKey" />.</summary>
    public static IReadOnlyDictionary<string, string?> Flatten<TEntry>(string blockKey, string name, TEntry entry)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(blockKey);
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(entry);

        var values = new Dictionary<string, string?>(StringComparer.Ordinal);
        Walk($"{ConfigKey.Path(blockKey)}:{name}", entry, values);
        return values;
    }

    /// <summary>Flattens a whole keyed block under <paramref name="blockKey" />.</summary>
    public static IReadOnlyDictionary<string, string?> FlattenBlock<TEntry>(
        string blockKey,
        IReadOnlyDictionary<string, TEntry> block)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(blockKey);
        ArgumentNullException.ThrowIfNull(block);

        var values = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (var (name, entry) in block)
            foreach (var (key, value) in Flatten(blockKey, name, entry!))
                values[key] = value;

        return values;
    }

    private static void Walk(string prefix, object node, IDictionary<string, string?> values)
    {
        foreach (var property in node.GetType().GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (property.GetIndexParameters().Length > 0) continue;

            var key = $"{prefix}:{ConfigKey.Segment(property.Name)}";
            var value = property.GetValue(node);

            if (value is null)
            {
                values[key] = null;
                continue;
            }

            if (IsScalar(property.PropertyType))
            {
                values[key] = Render(value);
                continue;
            }

            Walk(key, value, values);
        }
    }

    private static bool IsScalar(Type type) =>
        type.IsPrimitive || type.IsEnum || type == typeof(string) || type == typeof(decimal);

    private static string Render(object value) => value switch
    {
        // The binder parses booleans case-insensitively, but YAML and env layers both spell
        // them lowercase, so the flattened form matches what a real layer would carry.
        bool flag => flag ? "true" : "false",
        string text => text,
        // IsScalar has already narrowed the rest to primitives, enums, and decimal, every one
        // of which is IFormattable — so there is no unreachable fallback arm to leave untested.
        _ => ((IFormattable)value).ToString(null, CultureInfo.InvariantCulture),
    };
}
