namespace AtomiCloud.Diene.Interfaces;

/// <summary>How a metric sample is aggregated. Wire names are lowercase.</summary>
public enum MetricKind
{
    /// <summary>A monotonically accumulating value.</summary>
    Counter,

    /// <summary>An instantaneous value.</summary>
    Gauge,

    /// <summary>A distribution observation.</summary>
    Histogram,
}

/// <summary>One metric sample emitted by an application.</summary>
public sealed class MetricRecord
{
    /// <summary>Creates a metric record, normalizing the timestamp to UTC.</summary>
    /// <param name="timestamp">When the sample was observed.</param>
    /// <param name="name">The metric name.</param>
    /// <param name="kind">How the sample aggregates.</param>
    /// <param name="value">The observed numeric value.</param>
    /// <param name="unit">The declared unit, when the metric has one.</param>
    /// <param name="attributes">Structured context copied into the record.</param>
    public MetricRecord(
        DateTimeOffset timestamp,
        string name,
        MetricKind kind,
        double value,
        string? unit = null,
        IEnumerable<KeyValuePair<string, AttributeValue>>? attributes = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        Timestamp = timestamp.ToUniversalTime();
        Name = name;
        Kind = kind;
        Value = value;
        Unit = Option.FromNullable(unit);
        Attributes = SeamAttributes.Copy(attributes);
    }

    /// <summary>When the sample was observed, in UTC.</summary>
    public DateTimeOffset Timestamp { get; }

    /// <summary>The metric name.</summary>
    public string Name { get; }

    /// <summary>How the sample aggregates.</summary>
    public MetricKind Kind { get; }

    /// <summary>The observed numeric value.</summary>
    public double Value { get; }

    /// <summary>The declared unit, absent when the metric has none.</summary>
    public Option<string> Unit { get; }

    /// <summary>Structured context, ordered by key.</summary>
    public IReadOnlyDictionary<string, AttributeValue> Attributes { get; }

    /// <summary>Renders the record as <c>instant kind name=value</c>.</summary>
    public override string ToString() =>
        $"{SeamWire.Instant(Timestamp)} {SeamWire.Name(Kind)} {Name}={AttributeValue.Real(Value).Wire}";
}

/// <summary>
/// The metrics EMIT seam. <c>AtomiCloud.Diene.Otel</c> implements it; this library
/// only declares it, and the shipped TestHelper owns its in-memory mock.
/// </summary>
public interface IMetricsCollector
{
    /// <summary>Delivers one metric sample.</summary>
    Result<Unit, SeamError> Emit(MetricRecord record);
}
