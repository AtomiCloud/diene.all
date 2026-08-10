using AtomiCloud.Diene.Interfaces;

namespace AtomiCloud.Diene.CoreUtils;

/// <summary>
/// The bridge from this library's wire forms to the attribute maps carried by
/// the <c>ILoggerSink</c> and <c>IMetricsCollector</c> seams.
/// </summary>
/// <remarks>
/// The seams library declares attribute kinds for the values telemetry usually
/// carries, but a date, a time of day, and an exact decimal have no kind of
/// their own — encoding them ad hoc at each call site is how a fleet ends up
/// with three spellings of the same timestamp. These factories put the C0 form
/// on the wire instead, and <see cref="Normalize" /> makes attribute keys obey
/// the same canonical matching rule as config keys, so <c>request_id</c> emitted
/// by one service and <c>requestId</c> emitted by another aggregate as one
/// series.
/// </remarks>
public static class WireAttributes
{
    /// <summary>Carries a date as its <c>YYYY-MM-DD</c> wire form.</summary>
    public static AttributeValue Date(DateOnly value) => AttributeValue.Text(Wire.Format(value));

    /// <summary>Carries a time of day as its <c>HH:mm:ss</c> wire form.</summary>
    public static AttributeValue Time(TimeOnly value) => AttributeValue.Text(Wire.Format(value));

    /// <summary>
    /// Carries an exact decimal as a decimal string, never as the seam's
    /// double-precision <c>Real</c> kind.
    /// </summary>
    public static AttributeValue Decimal(decimal value) => AttributeValue.Text(Wire.Format(value));

    /// <summary>
    /// Rewrites every attribute key to its canonical form. A key that normalizes
    /// to nothing, or that collides with another key once normalized, is reported
    /// rather than silently dropped.
    /// </summary>
    public static Result<IReadOnlyDictionary<string, AttributeValue>, KeyError> Normalize(
        IEnumerable<KeyValuePair<string, AttributeValue>> attributes)
    {
        ArgumentNullException.ThrowIfNull(attributes);

        var normalized = new Dictionary<string, AttributeValue>(StringComparer.Ordinal);
        foreach (var (key, value) in attributes)
        {
            var canonical = KeyNormalizer.Canonical(key);
            if (canonical.Length == 0)
                return Result.Err<IReadOnlyDictionary<string, AttributeValue>, KeyError>(
                    new KeyError("attribute key must not normalize to empty", key));

            if (!normalized.TryAdd(canonical, value))
                return Result.Err<IReadOnlyDictionary<string, AttributeValue>, KeyError>(
                    new KeyError($"attribute key collides with another key at \"{canonical}\"", key));
        }

        return Result.Ok<IReadOnlyDictionary<string, AttributeValue>, KeyError>(SeamAttributes.Copy(normalized));
    }
}
