using System.Globalization;
using System.Text;

namespace AtomiCloud.Diene.CoreUtils;

/// <summary>
/// Deterministic kebab-case identifiers. The transform is byte-parity with the
/// sibling <c>@atomicloud/diene.core-utils</c> <c>slugify</c>, so the same input
/// yields the same identifier in every language of the family.
/// </summary>
public static class Slug
{
    /// <summary>
    /// Folds an arbitrary string into a deterministic kebab-case slug: NFKD
    /// normalization, combining-mark removal, lowercasing, then every run of
    /// non-alphanumeric characters collapsed to a single hyphen with leading and
    /// trailing hyphens stripped.
    /// </summary>
    public static string Slugify(string input)
    {
        ArgumentNullException.ThrowIfNull(input);

        var folded = new StringBuilder(input.Length);
        foreach (var character in input.Normalize(NormalizationForm.FormKD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark)
                folded.Append(char.ToLowerInvariant(character));
        }

        var slug = new StringBuilder(folded.Length);
        var pendingSeparator = false;
        foreach (var character in folded.ToString())
        {
            if (char.IsAsciiLetterLower(character) || char.IsAsciiDigit(character))
            {
                if (pendingSeparator && slug.Length > 0) slug.Append('-');
                pendingSeparator = false;
                slug.Append(character);
            }
            else
            {
                pendingSeparator = true;
            }
        }

        return slug.ToString();
    }

    /// <summary>
    /// Composes a <c>namespace:key</c> identifier from slugified parts. This is a
    /// total function: a part that slugifies to empty yields an error instead of
    /// an exception.
    /// </summary>
    public static Result<string, KeyError> NamespacedKey(string ns, string key)
    {
        ArgumentNullException.ThrowIfNull(ns);
        ArgumentNullException.ThrowIfNull(key);

        var slugNamespace = Slugify(ns);
        if (slugNamespace.Length == 0)
            return Result.Err<string, KeyError>(new KeyError("namespace must not be empty", ns));

        var slugKey = Slugify(key);
        if (slugKey.Length == 0)
            return Result.Err<string, KeyError>(new KeyError("key must not be empty", key));

        return Result.Ok<string, KeyError>($"{slugNamespace}:{slugKey}");
    }
}
