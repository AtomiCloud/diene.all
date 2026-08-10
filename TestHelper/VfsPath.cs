namespace AtomiCloud.Diene.Interfaces.TestHelper;

/// <summary>
/// The path policy of <see cref="InMemoryVfs"/>: forward slashes, no trailing
/// separator except at the root. Paths stay opaque to the seam contract; this is
/// one implementation's declared normalization, published so consumers writing
/// their own fakes can match it.
/// </summary>
public static class VfsPath
{
    /// <summary>The root path.</summary>
    public const string Root = "/";

    /// <summary>Normalizes separators and strips redundant and trailing slashes.</summary>
    public static string Normalize(string path)
    {
        ArgumentNullException.ThrowIfNull(path);
        var segments = path.Replace('\\', '/')
            .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return segments.Length == 0 ? Root : Root + string.Join('/', segments);
    }

    /// <summary>The parent of a normalized path, absent at the root.</summary>
    public static Option<string> Parent(string path)
    {
        var normalized = Normalize(path);
        if (string.Equals(normalized, Root, StringComparison.Ordinal)) return Option.None<string>();
        var cut = normalized.LastIndexOf('/');
        return Option.Some(cut <= 0 ? Root : normalized[..cut]);
    }

    /// <summary>Whether <paramref name="candidate"/> lies below <paramref name="ancestor"/>.</summary>
    public static bool IsBelow(string candidate, string ancestor)
    {
        var normalizedAncestor = Normalize(ancestor);
        var normalizedCandidate = Normalize(candidate);
        if (string.Equals(normalizedAncestor, Root, StringComparison.Ordinal))
        {
            return !string.Equals(normalizedCandidate, Root, StringComparison.Ordinal);
        }

        return normalizedCandidate.StartsWith(normalizedAncestor + Root, StringComparison.Ordinal);
    }

    /// <summary>Whether <paramref name="candidate"/> is a direct child of <paramref name="parent"/>.</summary>
    public static bool IsDirectChild(string candidate, string parent) =>
        IsBelow(candidate, parent) && Parent(candidate).Match(
            actual => string.Equals(actual, Normalize(parent), StringComparison.Ordinal),
            () => false);
}
