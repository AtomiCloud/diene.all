using System.Text.Json;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Interfaces;

namespace AtomiCloud.Diene.CoreUtils.App;

/// <summary>
/// The demo consumer: what a service actually does with this library. Every
/// method here is a shape a real caller reproduces — compose an identifier,
/// put a payload on the wire, read one back, and attach wire-formatted values
/// to telemetry.
/// </summary>
public static class Samples
{
    /// <summary>Composes a catalog identifier from untrusted namespace and title text.</summary>
    public static Result<string, KeyError> CatalogKey(string ns, string title) => Slug.NamespacedKey(ns, title);

    /// <summary>Serializes a receipt using the wire contract, with no per-property attributes.</summary>
    public static string ToWire(ShipmentReceipt receipt) =>
        JsonSerializer.Serialize(receipt, AtomiJson.DefaultOptions);

    /// <summary>
    /// Reads a receipt back. A malformed payload becomes a value, not an
    /// exception escaping into the caller's request pipeline.
    /// </summary>
    public static Result<ShipmentReceipt, WireFormatError> FromWire(string json)
    {
        try
        {
            var receipt = JsonSerializer.Deserialize<ShipmentReceipt>(json, AtomiJson.DefaultOptions);
            return receipt is null
                ? Result.Err<ShipmentReceipt, WireFormatError>(new WireFormatError("shipment receipt", json))
                : Result.Ok<ShipmentReceipt, WireFormatError>(receipt);
        }
        catch (JsonException exception)
        {
            return Result.Err<ShipmentReceipt, WireFormatError>(
                new WireFormatError("shipment receipt", exception.Message));
        }
    }

    /// <summary>
    /// Builds the attribute map a logger sink or metrics collector receives, with
    /// keys canonicalized so services that spell them differently still aggregate.
    /// </summary>
    public static Result<IReadOnlyDictionary<string, AttributeValue>, KeyError> Telemetry(ShipmentReceipt receipt)
    {
        ArgumentNullException.ThrowIfNull(receipt);
        return WireAttributes.Normalize(new Dictionary<string, AttributeValue>(StringComparer.Ordinal)
        {
            ["shipment_reference"] = AttributeValue.Text(receipt.Reference),
            ["shipped-on"] = WireAttributes.Date(receipt.ShippedOn),
            ["dailyCutoff"] = WireAttributes.Time(receipt.Cutoff),
            ["DeclaredValue"] = WireAttributes.Decimal(receipt.DeclaredValue),
            ["confirmed_at"] = AttributeValue.Instant(receipt.ConfirmedAt),
            ["transit_time"] = AttributeValue.Duration(receipt.TransitTime),
            ["tracking_number"] = AttributeValue.Integer(receipt.TrackingNumber),
        });
    }

    /// <summary>
    /// Reads an attribute by any casing or separator spelling of its key — the
    /// shape a config binder or a telemetry query needs, and the reason
    /// <see cref="KeyNormalizer.KeysMatch" /> exists.
    /// </summary>
    public static Result<AttributeValue, KeyError> Lookup(
        IReadOnlyDictionary<string, AttributeValue> attributes,
        string key)
    {
        ArgumentNullException.ThrowIfNull(attributes);
        foreach (var (candidate, value) in attributes)
        {
            if (KeyNormalizer.KeysMatch(candidate, key)) return Result.Ok<AttributeValue, KeyError>(value);
        }

        return Result.Err<AttributeValue, KeyError>(new KeyError("no attribute matches the key", key));
    }

    /// <summary>The receipt the demo run puts through the whole round trip.</summary>
    public static Result<ShipmentReceipt, WireFormatError> Sample() =>
        Wire.ParseTimeZone("Asia/Singapore").Map(zone => new ShipmentReceipt
        {
            Reference = CatalogKey("AtomiCloud", "Express Parcel").GetOr("shipment"),
            ShippedOn = new DateOnly(2026, 7, 25),
            Cutoff = new TimeOnly(17, 30, 0),
            ConfirmedAt = new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero),
            TransitTime = TimeSpan.FromMinutes(90),
            OriginZone = zone,
            DeclaredValue = 1249.50m,
            TrackingNumber = 9007199254740993L,
        });
}
