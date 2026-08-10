using FluentValidation;

namespace AtomiCloud.Diene.StandardConfig.Presets;

/// <summary>
/// The one validator shape every infra preset takes: a keyed map whose names survive the
/// canonical key rule intact and whose entries each satisfy their own validator.
/// </summary>
/// <remarks>
/// Written once here so a preset contributes its ENTRY rules only. The name rule is
/// <see cref="PresetKey.IsAcceptable" /> rather than the UPPERCASE contract itself, because by
/// the time an option block is bound the authored casing is gone — see <see cref="PresetKey" />.
/// Enforcing UPPERCASE AUTHORING is the TestHelper YAML audit's job; what belongs HERE is the
/// check that still bites at startup, so a service whose pool name carries stray punctuation
/// dies at <c>ValidateOnStart</c> rather than resolving a silently absent connection at first
/// use.
/// </remarks>
/// <typeparam name="TBlock">The preset's named block type.</typeparam>
/// <typeparam name="TEntry">The preset's entry type.</typeparam>
public abstract class KeyedBlockValidator<TBlock, TEntry> : AbstractValidator<TBlock>
    where TBlock : Dictionary<string, TEntry>
{
    /// <summary>Builds the keyed-map rules around <paramref name="entryValidator" />.</summary>
    protected KeyedBlockValidator(IValidator<TEntry> entryValidator)
    {
        RuleForEach(block => block.Keys)
            .Must(PresetKey.IsAcceptable)
            .WithMessage(
                $"connection-pool names must be UPPERCASE alphanumerics, matching {PresetKey.Pattern} as " +
                $"authored (R14) or {PresetKey.BoundPattern} once the canonical key rule has folded them");

        RuleForEach(block => block.Values).SetValidator(entryValidator);
    }
}
