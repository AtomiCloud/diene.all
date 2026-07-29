using AtomiCloud.Diene.AuthEngine.Tokens;

namespace AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;

/// <summary>
/// A clock the test drives. Expiry behaviour is the single hardest thing to test against
/// a real clock, because the interesting cases require waiting; advancing this instead
/// makes them instant and deterministic.
/// </summary>
/// <param name="now">The instant the clock starts at.</param>
public sealed class FakeAuthClock(DateTimeOffset now) : IAuthClock
{
    /// <summary>An arbitrary but stable instant used when a test does not care which one.</summary>
    public static readonly DateTimeOffset DefaultInstant = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);

    /// <summary>Creates a clock at <see cref="DefaultInstant" />.</summary>
    public FakeAuthClock()
        : this(DefaultInstant)
    {
    }

    /// <inheritdoc />
    public DateTimeOffset UtcNow { get; private set; } = now;

    /// <summary>Moves the clock forward by the supplied span.</summary>
    public void Advance(TimeSpan by) => this.UtcNow += by;

    /// <summary>Moves the clock to an absolute instant.</summary>
    public void Set(DateTimeOffset instant) => this.UtcNow = instant;
}
