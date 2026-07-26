using System.Collections.Immutable;

namespace AtomiCloud.Diene.Otel;

/// <summary>
/// The attribute-map invariants shared by every trace-seam record: keys are
/// non-blank and NUL-free, values are finite primitives, and the map is ordered and
/// immutable so two records carrying the same attributes compare equal regardless
/// of the order the caller supplied them in.
/// </summary>
public static class TraceAttributes
{
    /// <summary>The empty attribute map.</summary>
    public static IReadOnlyDictionary<string, AttributeValue> Empty { get; } =
        ImmutableSortedDictionary<string, AttributeValue>.Empty.WithComparers(StringComparer.Ordinal);

    /// <summary>
    /// Validates and normalizes caller-supplied attributes. Non-finite reals are
    /// rejected because no exporter can represent them.
    /// </summary>
    public static Result<IReadOnlyDictionary<string, AttributeValue>, TraceError> Check(
        IEnumerable<KeyValuePair<string, AttributeValue>>? attributes,
        string operation)
    {
        if (attributes is null) return Result.Ok<IReadOnlyDictionary<string, AttributeValue>, TraceError>(Empty);

        var checked_ = ImmutableSortedDictionary.CreateBuilder<string, AttributeValue>(StringComparer.Ordinal);
        foreach (var (key, value) in attributes)
        {
            if (string.IsNullOrWhiteSpace(key) || key.Contains('\u0000', StringComparison.Ordinal))
            {
                return TraceErrors.InvalidInput(
                    operation,
                    "Trace attribute names must be non-blank and NUL-free.");
            }

            if (!IsFinite(value))
            {
                return TraceErrors.InvalidInput(operation, "Trace attribute values must be finite primitives.");
            }

            checked_[key] = value;
        }

        return Result.Ok<IReadOnlyDictionary<string, AttributeValue>, TraceError>(checked_.ToImmutable());
    }

    /// <summary>Compares two attribute maps by content.</summary>
    public static bool Equal(
        IReadOnlyDictionary<string, AttributeValue> left,
        IReadOnlyDictionary<string, AttributeValue> right)
    {
        ArgumentNullException.ThrowIfNull(left);
        ArgumentNullException.ThrowIfNull(right);
        if (left.Count != right.Count) return false;
        foreach (var (key, value) in left)
        {
            if (!right.TryGetValue(key, out var other) || value != other) return false;
        }

        return true;
    }

    private static bool IsFinite(AttributeValue value) =>
        value.Kind != AttributeValueKind.Real || value.AsReal().Match(double.IsFinite, _ => false);
}
