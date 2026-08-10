namespace AtomiCloud.Diene.Interfaces;

/// <summary>
/// The process, environment, and clock boundary. Portable libraries take this
/// seam instead of touching <c>System.Environment</c> or <c>DateTimeOffset.UtcNow</c>
/// directly, so their behaviour is deterministic under test.
/// </summary>
public interface ISystem
{
    /// <summary>
    /// Reads one process environment variable. A successful <c>None</c> means the
    /// variable is absent; a successful <c>Some("")</c> means it is present and empty.
    /// </summary>
    Result<Option<string>, SeamError> Environment(string name);

    /// <summary>Returns the current working directory as an absolute path.</summary>
    Result<string, SeamError> CurrentDirectory();

    /// <summary>Returns the current instant in UTC.</summary>
    Result<DateTimeOffset, SeamError> NowUtc();

    /// <summary>Waits for the given duration, or fails with a cancellation error.</summary>
    Task<Result<Unit, SeamError>> Delay(TimeSpan duration, CancellationToken cancellationToken = default);
}
