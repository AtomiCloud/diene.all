namespace AtomiCloud.Diene.StandardConfig.Presets;

/// <summary>
/// Lookup over a resolved preset block, so <c>postgres.Named("MAIN")</c> reads the way a
/// service thinks about its connections.
/// </summary>
/// <remarks>
/// <para>
/// Two shapes on purpose. <see cref="Find{T}" /> is total and returns an
/// <see cref="Option{T}" /> — the form domain code composes with. <see cref="Named{T}" />
/// is the fail-fast form for composition roots, where a missing connection is a startup bug
/// and the only useful behaviour is to die loudly naming the keys that DO exist.
/// </para>
/// <para>
/// Both look up case-insensitively. A service writes <c>Named("MAIN")</c> because
/// <c>MAIN</c> is what R14 says it authored, but the config lib's canonical key rule folded
/// that to <c>main</c> before the binder ever saw it. Matching ordinally here would make the
/// contract-correct spelling the one that fails.
/// </para>
/// </remarks>
public static class KeyedBlock
{
    /// <summary>Looks up a named connection, returning None when it is absent.</summary>
    public static Option<T> Find<T>(this IReadOnlyDictionary<string, T> block, string key)
    {
        ArgumentNullException.ThrowIfNull(block);
        ArgumentNullException.ThrowIfNull(key);

        if (block.TryGetValue(key, out var exact)) return Option.Some(exact);

        foreach (var (name, entry) in block)
            if (string.Equals(name, key, StringComparison.OrdinalIgnoreCase))
                return Option.Some(entry);

        return Option.None<T>();
    }

    /// <summary>Looks up a named connection, throwing when it is absent.</summary>
    /// <exception cref="StandardConfigException">No connection is registered under <paramref name="key" />.</exception>
    public static T Named<T>(this IReadOnlyDictionary<string, T> block, string key)
    {
        if (block.Find(key).IsSome(out var entry)) return entry;

        var known = block.Count > 0 ? string.Join(", ", block.Keys.Order(StringComparer.Ordinal)) : "(none registered)";
        throw new StandardConfigException($"no \"{key}\" connection in this block; known keys: {known}");
    }
}
