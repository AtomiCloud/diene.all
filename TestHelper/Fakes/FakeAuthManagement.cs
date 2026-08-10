using System.Collections.ObjectModel;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;

/// <summary>A stateful, scriptable fake for every <see cref="IAuthManagement" /> operation.</summary>
public sealed class FakeAuthManagement : IAuthManagement
{
    private readonly Lock _gate = new();
    private readonly Dictionary<string, AuthManagementUser> _users = new(StringComparer.Ordinal);
    private readonly Dictionary<(string UserId, string Key), string> _claims = [];
    private readonly Queue<IDomainProblem> _failures = new();
    private readonly Queue<IDomainProblem> _getUserFailures = new();
    private readonly Queue<IDomainProblem> _mintFailures = new();
    private readonly List<string> _userLookups = [];
    private readonly List<string> _mintedEmails = [];
    private readonly List<(string UserId, string RoleId)> _assignedRoles = [];
    private readonly List<(string UserId, string RoleId)> _removedRoles = [];
    private readonly List<string> _deletedUsers = [];

    /// <summary>Gets or sets the one-time token returned by successful mint calls.</summary>
    public string OneTimeToken { get; set; } = "fake-one-time-token";

    /// <summary>Gets the user ids passed to <see cref="GetUser" />, in call order.</summary>
    public IReadOnlyList<string> UserLookups => this._userLookups;

    /// <summary>Gets the emails passed to <see cref="MintOneTimeToken" />, in call order.</summary>
    public IReadOnlyList<string> MintedEmails => this._mintedEmails;

    /// <summary>Gets the current claim values keyed by user and claim name.</summary>
    public IReadOnlyDictionary<(string UserId, string Key), string> Claims =>
        new ReadOnlyDictionary<(string UserId, string Key), string>(this._claims);

    /// <summary>Gets successful role assignments in call order.</summary>
    public IReadOnlyList<(string UserId, string RoleId)> AssignedRoles => this._assignedRoles;

    /// <summary>Gets successful role removals in call order.</summary>
    public IReadOnlyList<(string UserId, string RoleId)> RemovedRoles => this._removedRoles;

    /// <summary>Gets successfully deleted user ids in call order.</summary>
    public IReadOnlyList<string> DeletedUsers => this._deletedUsers;

    /// <summary>Adds or replaces a user returned by the fake.</summary>
    public void SetUser(AuthManagementUser user)
    {
        ArgumentNullException.ThrowIfNull(user);
        ArgumentException.ThrowIfNullOrWhiteSpace(user.Subject);
        lock (this._gate) this._users[user.Subject] = user;
    }

    /// <summary>Makes the next management operation return a typed failure.</summary>
    public void FailNext(IDomainProblem problem)
    {
        ArgumentNullException.ThrowIfNull(problem);
        lock (this._gate) this._failures.Enqueue(problem);
    }

    /// <summary>Makes the next user lookup return the supplied typed failure.</summary>
    public void FailNextGetUser(IDomainProblem problem) => this.Enqueue(this._getUserFailures, problem);

    /// <summary>Makes the next one-time-token mint return the supplied typed failure.</summary>
    public void FailNextMint(IDomainProblem problem) => this.Enqueue(this._mintFailures, problem);

    /// <inheritdoc />
    public Task<Result<Option<AuthManagementUser>, IDomainProblem>> GetUser(
        string userId,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (this._gate)
        {
            if (string.IsNullOrWhiteSpace(userId)) return Failure<Option<AuthManagementUser>>();
            this._userLookups.Add(userId);
            if (this.TakeFailure(this._getUserFailures) is { } failure)
            {
                return Failure<Option<AuthManagementUser>>(failure);
            }
            return Success(this._users.TryGetValue(userId, out var user)
                ? Option.Some(user)
                : Option.None<AuthManagementUser>());
        }
    }

    /// <inheritdoc />
    public Task<Result<string, IDomainProblem>> MintOneTimeToken(
        string email,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (this._gate)
        {
            if (string.IsNullOrWhiteSpace(email)) return Failure<string>();
            this._mintedEmails.Add(email);
            if (this.TakeFailure(this._mintFailures) is { } failure) return Failure<string>(failure);
            return Success(this.OneTimeToken);
        }
    }

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> SetClaim(
        string userId,
        string key,
        string value,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (this._gate)
        {
            if (Invalid(userId, key) || string.IsNullOrWhiteSpace(value)) return Failure<Unit>();
            if (this.TakeFailure(this._failures) is { } failure) return Failure<Unit>(failure);
            this._claims[(userId, key)] = value;
            return Success(new Unit());
        }
    }

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> RemoveClaim(
        string userId,
        string key,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (this._gate)
        {
            if (Invalid(userId, key)) return Failure<Unit>();
            if (this.TakeFailure(this._failures) is { } failure) return Failure<Unit>(failure);
            this._claims.Remove((userId, key));
            return Success(new Unit());
        }
    }

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> AssignRole(
        string userId,
        string roleId,
        CancellationToken cancellationToken = default) =>
        this.ChangeRole(userId, roleId, this._assignedRoles, cancellationToken);

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> RemoveRole(
        string userId,
        string roleId,
        CancellationToken cancellationToken = default) =>
        this.ChangeRole(userId, roleId, this._removedRoles, cancellationToken);

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> DeleteUser(
        string userId,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (this._gate)
        {
            if (string.IsNullOrWhiteSpace(userId)) return Failure<Unit>();
            if (this.TakeFailure(this._failures) is { } failure) return Failure<Unit>(failure);
            this._users.Remove(userId);
            this._deletedUsers.Add(userId);
            return Success(new Unit());
        }
    }

    private Task<Result<Unit, IDomainProblem>> ChangeRole(
        string userId,
        string roleId,
        ICollection<(string UserId, string RoleId)> calls,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (this._gate)
        {
            if (Invalid(userId, roleId)) return Failure<Unit>();
            if (this.TakeFailure(this._failures) is { } failure) return Failure<Unit>(failure);
            calls.Add((userId, roleId));
            return Success(new Unit());
        }
    }

    private void Enqueue(Queue<IDomainProblem> failures, IDomainProblem problem)
    {
        ArgumentNullException.ThrowIfNull(problem);
        lock (this._gate) failures.Enqueue(problem);
    }

    private IDomainProblem? TakeFailure(Queue<IDomainProblem> specific)
    {
        if (specific.Count > 0) return specific.Dequeue();
        return this._failures.Count == 0 ? null : this._failures.Dequeue();
    }

    private static bool Invalid(string first, string second) =>
        string.IsNullOrWhiteSpace(first) || string.IsNullOrWhiteSpace(second);

    private static Task<Result<T, IDomainProblem>> Success<T>(T value) =>
        Task.FromResult(Result.Ok<T, IDomainProblem>(value));

    private static Task<Result<T, IDomainProblem>> Failure<T>(IDomainProblem? problem = null) =>
        Task.FromResult(Result.Err<T, IDomainProblem>(problem ?? AuthProblems.MalformedToken()));
}
