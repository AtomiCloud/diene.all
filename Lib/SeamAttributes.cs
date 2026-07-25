using System.Collections.Immutable;

namespace AtomiCloud.Diene.Interfaces;

/// <summary>Ordered, independently owned attribute maps for log and metric records.</summary>
public static class SeamAttributes
{
    /// <summary>The empty attribute map.</summary>
    public static IReadOnlyDictionary<string, AttributeValue> Empty { get; } =
        ImmutableSortedDictionary<string, AttributeValue>.Empty.WithComparers(StringComparer.Ordinal);

    /// <summary>Copies caller-supplied attributes into an immutable, key-ordered map.</summary>
    public static IReadOnlyDictionary<string, AttributeValue> Copy(
        IEnumerable<KeyValuePair<string, AttributeValue>>? attributes) =>
        attributes is null
            ? Empty
            : ImmutableSortedDictionary.CreateRange(StringComparer.Ordinal, attributes);
}
