using System.Collections.ObjectModel;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;

/// <summary>A snapshot of one record held by <see cref="InMemoryDeferredTokenStore" />.</summary>
// Every field is public test-observation state even when this repository does not assert it.
// ReSharper disable NotAccessedPositionalProperty.Global
public sealed record DeferredStoreSnapshot(
    DeferredPayload Payload,
    DateTimeOffset ExpiresAt,
    TimeSpan Ttl,
    DeferredTokenState State);
// ReSharper restore NotAccessedPositionalProperty.Global

/// <summary>
/// Lock-based deferred-token fake with the same atomic claim and terminal-state
/// invariants required of a persistent production adapter.
/// </summary>
public sealed class InMemoryDeferredTokenStore(IAuthClock? clock = null) : IDeferredTokenStore
{
    private readonly Lock _gate = new();
    private readonly Dictionary<string, DeferredStoreSnapshot> _records = new(StringComparer.Ordinal);
    private readonly Queue<IDomainProblem> _putFailures = new();
    private readonly Queue<IDomainProblem> _consumeFailures = new();
    private readonly Queue<IDomainProblem> _settleFailures = new();
    private readonly IAuthClock _clock = clock ?? new FakeAuthClock();

    /// <summary>Gets a stable snapshot of every stored record, keyed by digest.</summary>
    public IReadOnlyDictionary<string, DeferredStoreSnapshot> Records
    {
        get
        {
            lock (this._gate)
            {
                return new ReadOnlyDictionary<string, DeferredStoreSnapshot>(
                    new Dictionary<string, DeferredStoreSnapshot>(this._records, StringComparer.Ordinal));
            }
        }
    }

    /// <summary>Makes the next <see cref="Put" /> return the supplied typed failure.</summary>
    public void FailNextPut(IDomainProblem problem) => this.Enqueue(this._putFailures, problem);

    /// <summary>Makes the next <see cref="Consume" /> return the supplied typed failure.</summary>
    public void FailNextConsume(IDomainProblem problem) => this.Enqueue(this._consumeFailures, problem);

    /// <summary>Makes the next <see cref="Settle" /> return the supplied typed failure.</summary>
    public void FailNextSettle(IDomainProblem problem) => this.Enqueue(this._settleFailures, problem);

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> Put(
        string tokenDigest,
        DeferredPayload payload,
        TimeSpan ttl,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (this._gate)
        {
            if (TakeFailure(this._putFailures) is { } failure) return Failure<Unit>(failure);
            if (string.IsNullOrWhiteSpace(tokenDigest) || payload is null || ttl <= TimeSpan.Zero ||
                this._records.ContainsKey(tokenDigest))
            {
                return Failure<Unit>(new AppHandoffExpired());
            }

            this._records[tokenDigest] = new DeferredStoreSnapshot(
                payload,
                this._clock.UtcNow + ttl,
                ttl,
                DeferredTokenState.Active);
            return Success(new Unit());
        }
    }

    /// <inheritdoc />
    public Task<Result<Option<DeferredPayload>, IDomainProblem>> Consume(
        string tokenDigest,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (this._gate)
        {
            if (TakeFailure(this._consumeFailures) is { } failure) return Failure<Option<DeferredPayload>>(failure);
            if (!this._records.TryGetValue(tokenDigest, out var record) ||
                record.State != DeferredTokenState.Active || this._clock.UtcNow >= record.ExpiresAt)
            {
                return Success(Option.None<DeferredPayload>());
            }

            this._records[tokenDigest] = record with { State = DeferredTokenState.Claimed };
            return Success(Option.Some(record.Payload));
        }
    }

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> Settle(
        string tokenDigest,
        DeferredTokenState state,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (this._gate)
        {
            if (TakeFailure(this._settleFailures) is { } failure) return Failure<Unit>(failure);
            if (state is not (DeferredTokenState.Consumed or DeferredTokenState.Revoked) ||
                !this._records.TryGetValue(tokenDigest, out var record) ||
                record.State != DeferredTokenState.Claimed)
            {
                return Failure<Unit>(new AppHandoffExpired());
            }

            this._records[tokenDigest] = record with { State = state };
            return Success(new Unit());
        }
    }

    private void Enqueue(Queue<IDomainProblem> failures, IDomainProblem problem)
    {
        ArgumentNullException.ThrowIfNull(problem);
        lock (this._gate) failures.Enqueue(problem);
    }

    private static IDomainProblem? TakeFailure(Queue<IDomainProblem> failures) =>
        failures.Count == 0 ? null : failures.Dequeue();

    private static Task<Result<T, IDomainProblem>> Success<T>(T value) =>
        Task.FromResult(Result.Ok<T, IDomainProblem>(value));

    private static Task<Result<T, IDomainProblem>> Failure<T>(IDomainProblem problem) =>
        Task.FromResult(Result.Err<T, IDomainProblem>(problem));
}
