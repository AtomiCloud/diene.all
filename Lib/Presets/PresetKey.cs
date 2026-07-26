using System.Text.RegularExpressions;

namespace AtomiCloud.Diene.StandardConfig.Presets;

/// <summary>
/// The keyed multi-instance convention every infra preset follows.
/// </summary>
/// <remarks>
/// <para>
/// A preset is never a single connection: it is a map of NAMED connections
/// (<c>MAIN</c>, <c>REPLICA</c>, <c>ANALYTICS</c>) whose keys are UPPERCASE by contract
/// (R14, C0 §3). Adding a second instance is therefore pure YAML — no schema surgery, no
/// new option type, no code change in the lib or in the service.
/// </para>
/// <para>
/// TWO patterns, because .NET sees the name twice in two different spellings. As AUTHORED
/// in YAML or an environment variable it must match <see cref="Pattern" />. By the time the
/// configuration binder hands it over it has been through the config lib's canonical key
/// rule, which folds case and strips <c>_ - . </c> separators — so <c>MAIN</c> arrives as
/// <c>main</c> and <c>READ_REPLICA</c> as <c>readreplica</c>. The bound spelling is what
/// <see cref="IsBoundNameValid" /> can still check, and it is genuinely weaker: enforcing the
/// UPPERCASE contract itself requires reading the SOURCE, which is what the TestHelper's YAML
/// audit is for.
/// </para>
/// </remarks>
public static class PresetKey
{
    /// <summary>The UPPERCASE connection-pool name contract, as authored (R14).</summary>
    public const string Pattern = "^[A-Z][A-Z0-9_]*$";

    /// <summary>
    /// What an authored name looks like after the config lib's canonical key rule: case
    /// folded, separators stripped.
    /// </summary>
    public const string BoundPattern = "^[a-z][a-z0-9]*$";

    // Plain compiled regexes rather than [GeneratedRegex]: the source generator emits a
    // vectorized scan path this library never reaches on two-token patterns, and an
    // unreachable branch inside generated code is not something a coverage ledger can be
    // honest about without an exclusion list.
    private static readonly Regex UppercaseRegex = new(Pattern, RegexOptions.CultureInvariant);
    private static readonly Regex BoundRegex = new(BoundPattern, RegexOptions.CultureInvariant);

    /// <summary>Whether <paramref name="key" /> obeys the authored UPPERCASE contract.</summary>
    public static bool IsValid(string? key) => key is not null && UppercaseRegex.IsMatch(key);

    /// <summary>
    /// Whether <paramref name="key" /> could have come from a valid authored name.
    /// </summary>
    /// <remarks>
    /// This is the strongest check available once the binder has run. It still catches the
    /// mistakes that matter at that layer — punctuation the canonicalizer does not strip
    /// (<c>my@pool</c>), a leading digit, an empty name — but it CANNOT tell an UPPERCASE
    /// author from a lowercase one, because that difference no longer exists.
    /// </remarks>
    public static bool IsBoundNameValid(string? key) => key is not null && BoundRegex.IsMatch(key);

    /// <summary>
    /// Whether <paramref name="key" /> is a legitimate connection name in EITHER spelling.
    /// </summary>
    /// <remarks>
    /// A block reaches a validator by one of two routes, and they disagree on casing. Through
    /// the configuration binder the name has been folded (<c>main</c>); built directly — as a
    /// TestHelper container helper or a hand-written fixture does — it is still authored
    /// (<c>MAIN</c>). Both are correct, so the block validator accepts both, and what it
    /// rejects is a name that is NEITHER: mixed case (<c>Main</c>), punctuation
    /// (<c>my@pool</c>), a leading digit, or nothing at all.
    /// </remarks>
    public static bool IsAcceptable(string? key) => IsValid(key) || IsBoundNameValid(key);
}
