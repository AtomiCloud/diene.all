namespace AtomiCloud.Diene.Results;

/// <summary>Represents a successful operation with no meaningful value.</summary>
public readonly struct Unit : IEquatable<Unit>
{
    /// <inheritdoc />
    public bool Equals(Unit other) => true;

    /// <inheritdoc />
    public override bool Equals(object? obj) => obj is Unit;

    /// <inheritdoc />
    public override int GetHashCode() => 0;

    /// <inheritdoc />
    public override string ToString() => "()";

    /// <summary>Determines whether two unit values are equal.</summary>
    public static bool operator ==(Unit left, Unit right) => left.Equals(right);

    /// <summary>Determines whether two unit values are unequal.</summary>
    public static bool operator !=(Unit left, Unit right) => !left.Equals(right);
}
