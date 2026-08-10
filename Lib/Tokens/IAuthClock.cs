namespace AtomiCloud.Diene.AuthEngine.Tokens;

/// <summary>
/// The clock boundary. Every expiry decision reads the instant through this seam so no
/// wall clock is consulted implicitly and tests inject a fixed instant instead.
/// </summary>
public interface IAuthClock
{
    /// <summary>Gets the current UTC instant.</summary>
    DateTimeOffset UtcNow { get; }
}

/// <summary>The production clock, reading the real UTC instant.</summary>
public sealed class SystemAuthClock : IAuthClock
{
    /// <summary>Gets a shared instance.</summary>
    public static SystemAuthClock Instance { get; } = new();

    /// <inheritdoc />
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;
}
