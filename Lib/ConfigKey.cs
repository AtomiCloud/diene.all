using AtomiCloud.Diene.CoreUtils;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.Diene.Config;

/// <summary>
/// Applies the ONE canonical key rule from C0 §3 to configuration paths, so that every
/// layer agrees on how a key is spelled before the binder ever sees it.
/// </summary>
/// <remarks>
/// <para>
/// The .NET configuration stack is already case-insensitive, but it is not
/// separator-insensitive: a YAML <c>error_portal:</c> key and an
/// <c>ATOMI_ERROR_PORTAL__ENABLED</c> environment variable would otherwise land on
/// different configuration keys and silently fail to override each other. Reducing every
/// segment through <see cref="KeyNormalizer.Canonical" /> collapses the snake, kebab, camel,
/// and Pascal spellings onto one key, which then binds to a Pascal option property because
/// the binder's own lookup is case-insensitive.
/// </para>
/// <para>
/// This is the whole of what the .NET port takes from bun's config machinery: provider
/// layering is the merge, and the configuration binder owns env coercion.
/// </para>
/// </remarks>
public static class ConfigKey
{
    /// <summary>Reduces a single path segment to its canonical spelling.</summary>
    public static string Segment(string segment) => KeyNormalizer.Canonical(segment);

    /// <summary>
    /// Reduces every segment of a <c>:</c>-delimited configuration path to its canonical
    /// spelling, leaving the delimiters in place.
    /// </summary>
    public static string Path(string path)
    {
        ArgumentNullException.ThrowIfNull(path);
        return string.Join(
            ConfigurationPath.KeyDelimiter,
            path.Split(ConfigurationPath.KeyDelimiter).Select(Segment));
    }
}
