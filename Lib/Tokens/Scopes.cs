namespace AtomiCloud.Diene.AuthEngine.Tokens;

/// <summary>Parsing and comparison for the space-delimited OAuth <c>scope</c> claim.</summary>
public static class Scopes
{
    /// <summary>
    /// Splits a scope claim into its values, discarding empty entries. A null or blank
    /// claim yields an empty set rather than a failure: a token with no scopes is a
    /// legitimate token that simply grants nothing.
    /// </summary>
    public static IReadOnlyList<string> Parse(string? claim) =>
        string.IsNullOrWhiteSpace(claim)
            ? []
            : claim.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    /// <summary>Returns the required scopes that are absent from the granted set.</summary>
    public static IReadOnlyList<string> Missing(
        IEnumerable<string> granted,
        IEnumerable<string> required)
    {
        ArgumentNullException.ThrowIfNull(granted);
        ArgumentNullException.ThrowIfNull(required);

        var have = new HashSet<string>(granted, StringComparer.Ordinal);
        return [.. required.Where(scope => !have.Contains(scope))];
    }
}
