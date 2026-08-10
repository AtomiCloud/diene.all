using System.Text;

namespace AtomiCloud.Diene.CoreUtils;

/// <summary>
/// The one canonical key-matching rule from the C0 §3 config contract:
/// <c>snake_case</c>, <c>kebab-case</c>, <c>camelCase</c>, and <c>PascalCase</c>
/// spellings of the same key all match.
/// </summary>
/// <remarks>
/// This is the ONLY part of bun's config machinery that survives into .NET.
/// Provider layering already IS the merge and the configuration binder already
/// owns <c>&lt;Prefix&gt;A__B</c> env coercion, so neither is ported; what the
/// framework does not do is match a YAML <c>error_portal:</c> key against an
/// <c>ErrorPortal</c> option, which is exactly what this type supplies to the
/// Config lib's YAML provider.
/// </remarks>
public static class KeyNormalizer
{
    /// <summary>
    /// Reduces a key to its canonical form: separators dropped, casing folded, and
    /// camel/Pascal humps left in place so that <c>error_portal</c>,
    /// <c>error-portal</c>, <c>errorPortal</c>, and <c>ErrorPortal</c> all reduce
    /// to <c>errorportal</c>.
    /// </summary>
    public static string Canonical(string key)
    {
        ArgumentNullException.ThrowIfNull(key);

        var canonical = new StringBuilder(key.Length);
        foreach (var character in key)
        {
            if (character is '_' or '-' or ' ' or '.') continue;
            canonical.Append(char.ToLowerInvariant(character));
        }

        return canonical.ToString();
    }

    /// <summary>Determines whether two keys name the same thing under the canonical rule.</summary>
    public static bool KeysMatch(string a, string b) =>
        string.Equals(Canonical(a), Canonical(b), StringComparison.Ordinal);
}
