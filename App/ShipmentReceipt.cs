namespace AtomiCloud.Diene.CoreUtils.App;

/// <summary>
/// An illustrative payload that carries one value of every C0 wire form, so the
/// demo exercises the whole contract rather than a convenient corner of it.
/// </summary>
public sealed record ShipmentReceipt
{
    /// <summary>The catalog identifier, composed through the slug helpers.</summary>
    public required string Reference { get; init; }

    /// <summary>The calendar day the shipment left the warehouse.</summary>
    public required DateOnly ShippedOn { get; init; }

    /// <summary>The daily cutoff, as a wall-clock time of day.</summary>
    public required TimeOnly Cutoff { get; init; }

    /// <summary>The exact moment the carrier confirmed receipt.</summary>
    public required DateTimeOffset ConfirmedAt { get; init; }

    /// <summary>The quoted transit time.</summary>
    public required TimeSpan TransitTime { get; init; }

    /// <summary>The origin warehouse timezone, as an IANA id.</summary>
    public required TimeZoneInfo OriginZone { get; init; }

    /// <summary>The declared value — an exact decimal, never a float.</summary>
    public required decimal DeclaredValue { get; init; }

    /// <summary>The carrier tracking number, well past the JSON safe-integer range.</summary>
    public required long TrackingNumber { get; init; }
}
