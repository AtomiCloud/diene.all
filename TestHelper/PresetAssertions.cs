using AtomiCloud.Diene.StandardConfig.Presets;
using FluentAssertions;
using FluentAssertions.Execution;
using FluentAssertions.Primitives;
using FluentValidation;

namespace AtomiCloud.Diene.StandardConfig.TestHelper;

/// <summary>Entry points for asserting on a resolved preset block.</summary>
public static class PresetAssertionExtensions
{
    /// <summary>Starts an assertion chain over a keyed preset block.</summary>
    /// <remarks>
    /// Deliberately NOT named <c>Should</c>. A preset block binds as a
    /// <c>Dictionary&lt;string, TEntry&gt;</c>, which FluentAssertions already extends, so a
    /// second <c>Should</c> would be ambiguous at every call site and would hide the stock
    /// dictionary assertions consumers also want.
    /// </remarks>
    public static PresetBlockAssertions<TEntry> ShouldAsPresetBlock<TEntry>(
        this IReadOnlyDictionary<string, TEntry> subject) => new(subject);
}

/// <summary>
/// Assertions over a keyed preset block — the three checks every consumer would otherwise
/// write by hand for each preset they compose.
/// </summary>
/// <typeparam name="TEntry">The preset's entry type.</typeparam>
public sealed class PresetBlockAssertions<TEntry>(IReadOnlyDictionary<string, TEntry> subject)
    : ReferenceTypeAssertions<IReadOnlyDictionary<string, TEntry>, PresetBlockAssertions<TEntry>>(subject)
{
    /// <inheritdoc />
    protected override string Identifier => "preset block";

    /// <summary>Asserts a named connection is present, and continues on its entry.</summary>
    public AndWhichConstraint<PresetBlockAssertions<TEntry>, TEntry> HaveConnection(
        string key,
        string because = "",
        params object[] becauseArgs)
    {
        var found = Subject is null ? Option.None<TEntry>() : Subject.Find(key);
        var present = found.IsSome(out var entry);

        string[] known = Subject is null ? [] : [.. Subject.Keys.Order(StringComparer.Ordinal)];

        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(present)
            .FailWith(
                $"Expected the {Identifier} to have connection {{0}}{{reason}}, but its keys were {{1}}.",
                key,
                known);

        return new AndWhichConstraint<PresetBlockAssertions<TEntry>, TEntry>(this, present ? entry! : default!);
    }

    /// <summary>Asserts every bound connection name survived the canonical key rule intact (R14).</summary>
    public AndConstraint<PresetBlockAssertions<TEntry>> HaveWellFormedConnectionNames(
        string because = "",
        params object[] becauseArgs)
    {
        var offenders = Subject is null
            ? []
            : Subject.Keys.Where(key => !PresetKey.IsAcceptable(key)).Order(StringComparer.Ordinal).ToArray();

        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(offenders.Length == 0)
            .FailWith(
                $"Expected every {Identifier} connection name to match {{0}}{{reason}}, but {{1}} did not.",
                $"{PresetKey.Pattern} or {PresetKey.BoundPattern}",
                offenders);

        return new AndConstraint<PresetBlockAssertions<TEntry>>(this);
    }

    /// <summary>Asserts the block satisfies its preset validator.</summary>
    public AndConstraint<PresetBlockAssertions<TEntry>> BeValidAgainst<TBlock>(
        IValidator<TBlock> validator,
        string because = "",
        params object[] becauseArgs)
        where TBlock : Dictionary<string, TEntry>, new()
    {
        ArgumentNullException.ThrowIfNull(validator);

        var block = new TBlock();
        if (Subject is not null)
            foreach (var (name, entry) in Subject)
                block[name] = entry;

        var result = validator.Validate(block);

        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(result.IsValid)
            .FailWith(
                $"Expected the {Identifier} to be valid{{reason}}, but validation reported {{0}}.",
                result.Errors.Select(failure => failure.ErrorMessage).ToArray());

        return new AndConstraint<PresetBlockAssertions<TEntry>>(this);
    }
}
