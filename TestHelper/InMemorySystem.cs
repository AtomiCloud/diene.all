namespace AtomiCloud.Diene.Interfaces.TestHelper;

/// <summary>
/// A deterministic <see cref="ISystem"/> with a settable clock, an in-memory
/// environment, and a fault queue. Consumers use it to test code that reads the
/// environment or the clock without touching the host process.
/// </summary>
public sealed class InMemorySystem : ISystem
{
    private readonly Lock _gate = new();
    private readonly Dictionary<string, string> _environment;
    private readonly Queue<SeamError> _failures = new();
    private readonly List<TimeSpan> _requestedDelays = [];
    private DateTimeOffset _now;
    private string _directory;

    /// <summary>Creates a system seam with a fixed clock and environment.</summary>
    /// <param name="now">The instant the clock reports; defaults to the C0 epoch anchor.</param>
    /// <param name="directory">The working directory the seam reports.</param>
    /// <param name="environment">The initial environment variables.</param>
    public InMemorySystem(
        DateTimeOffset? now = null,
        string directory = "/work",
        IEnumerable<KeyValuePair<string, string>>? environment = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        _now = (now ?? new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero)).ToUniversalTime();
        _directory = directory;
        _environment = environment is null
            ? new Dictionary<string, string>(StringComparer.Ordinal)
            : new Dictionary<string, string>(environment, StringComparer.Ordinal);
    }

    /// <summary>The durations passed to <see cref="Delay"/>, in call order.</summary>
    public IReadOnlyList<TimeSpan> RequestedDelays
    {
        get
        {
            lock (_gate) return [.. _requestedDelays];
        }
    }

    /// <summary>Sets one environment variable.</summary>
    public void SetEnvironment(string name, string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(value);
        lock (_gate) _environment[name] = value;
    }

    /// <summary>Removes one environment variable.</summary>
    public void RemoveEnvironment(string name)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        lock (_gate) _environment.Remove(name);
    }

    /// <summary>Sets the working directory the seam reports.</summary>
    public void SetDirectory(string directory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        lock (_gate) _directory = directory;
    }

    /// <summary>Sets the instant the clock reports.</summary>
    public void SetNow(DateTimeOffset now)
    {
        lock (_gate) _now = now.ToUniversalTime();
    }

    /// <summary>Advances the clock.</summary>
    public void Advance(TimeSpan delta)
    {
        lock (_gate) _now = _now.Add(delta);
    }

    /// <summary>Queues one failure to be returned by the next seam call.</summary>
    public void EnqueueFailure(SeamError error)
    {
        ArgumentNullException.ThrowIfNull(error);
        lock (_gate) _failures.Enqueue(error);
    }

    /// <inheritdoc />
    public Result<Option<string>, SeamError> Environment(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return SeamErrors.InvalidArgument(SeamKind.System, nameof(name), "The variable name must not be blank.");
        }

        lock (_gate)
        {
            if (_failures.TryDequeue(out var failure)) return failure;
            return Result.Ok<Option<string>, SeamError>(
                _environment.TryGetValue(name, out var value) ? Option.Some(value) : Option.None<string>());
        }
    }

    /// <inheritdoc />
    public Result<string, SeamError> CurrentDirectory()
    {
        lock (_gate)
        {
            if (_failures.TryDequeue(out var failure)) return failure;
            return Result.Ok<string, SeamError>(_directory);
        }
    }

    /// <inheritdoc />
    public Result<DateTimeOffset, SeamError> NowUtc()
    {
        lock (_gate)
        {
            if (_failures.TryDequeue(out var failure)) return failure;
            return Result.Ok<DateTimeOffset, SeamError>(_now);
        }
    }

    /// <inheritdoc />
    public Task<Result<Unit, SeamError>> Delay(TimeSpan duration, CancellationToken cancellationToken = default)
    {
        lock (_gate)
        {
            _requestedDelays.Add(duration);
            if (_failures.TryDequeue(out var failure))
            {
                return Task.FromResult(Result.Err<Unit, SeamError>(failure));
            }

            if (cancellationToken.IsCancellationRequested)
            {
                return Task.FromResult(Result.Err<Unit, SeamError>(SeamErrors.Cancelled(SeamKind.System, "delay")));
            }

            _now = _now.Add(duration);
            return Task.FromResult(Result.Ok<Unit, SeamError>(default));
        }
    }
}
