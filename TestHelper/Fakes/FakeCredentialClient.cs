using AtomiCloud.Diene.AuthEngine.Client;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;

/// <summary>
/// An in-memory <see cref="ICredentialClient" />. This is the network boundary a consumer
/// must fake to test its own code without reaching an identity provider.
/// </summary>
/// <remarks>
/// It counts calls as well as answering them, because the properties worth asserting
/// about a token cache are mostly about how MANY times the IdP was called — that a
/// second read was served from cache, or that a burst collapsed into one acquisition.
/// </remarks>
public sealed class FakeCredentialClient : ICredentialClient
{
    private readonly Dictionary<string, Queue<Result<TokenResponse, IDomainProblem>>> _scripted =
        new(StringComparer.Ordinal);

    private readonly List<string> _revoked = [];

    /// <summary>Gets how many times a token was acquired.</summary>
    public int AcquireCount { get; private set; }

    /// <summary>Gets how many times a refresh was performed.</summary>
    public int RefreshCount { get; private set; }

    /// <summary>Gets the subjects whose sessions were revoked, in call order.</summary>
    public IReadOnlyList<string> RevokedUsers => this._revoked;

    /// <summary>Gets or sets the token returned when no scripted response remains.</summary>
    public Result<TokenResponse, IDomainProblem> Default { get; set; } =
        Result.Ok<TokenResponse, IDomainProblem>(
            new TokenResponse("fake-access-token", DateTimeOffset.MaxValue));

    /// <summary>Gets or sets the refresh token handed back by <see cref="RefreshAsync" />.</summary>
    public string RotatedRefreshToken { get; set; } = "fake-rotated-refresh-token";

    /// <summary>Gets or sets the outcome of a revocation call.</summary>
    public Result<Unit, IDomainProblem> RevokeOutcome { get; set; } =
        Result.Ok<Unit, IDomainProblem>(new Unit());

    /// <summary>
    /// Queues one response for a resource. Successive calls consume the queue in order,
    /// which is how a test expresses "the first acquisition succeeds and the renewal
    /// fails" without reaching for a mocking framework.
    /// </summary>
    /// <remarks>
    /// Returns void rather than <c>this</c>. A fluent return that no caller chains is
    /// surface nobody uses; queue order is already expressed by call order.
    /// </remarks>
    public void Script(string resource, Result<TokenResponse, IDomainProblem> response)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(resource);

        if (!this._scripted.TryGetValue(resource, out var queue))
        {
            queue = new Queue<Result<TokenResponse, IDomainProblem>>();
            this._scripted[resource] = queue;
        }

        queue.Enqueue(response);
    }

    /// <summary>Queues a successful token for a resource, expiring at the supplied instant.</summary>
    public void ScriptToken(string resource, string token, DateTimeOffset expiresAt) =>
        this.Script(resource, Result.Ok<TokenResponse, IDomainProblem>(new TokenResponse(token, expiresAt)));

    /// <summary>Queues a failure for a resource.</summary>
    public void ScriptFailure(string resource, IDomainProblem problem) =>
        this.Script(resource, Result.Err<TokenResponse, IDomainProblem>(problem));

    /// <inheritdoc />
    public Task<Result<TokenResponse, IDomainProblem>> AcquireAsync(
        string resource,
        IReadOnlyList<string> scopes,
        CancellationToken cancellationToken = default)
    {
        this.AcquireCount++;

        if (string.IsNullOrWhiteSpace(resource))
        {
            return Task.FromResult(
                Result.Err<TokenResponse, IDomainProblem>(AuthProblems.AudienceMismatch()));
        }

        return Task.FromResult(this.Next(resource));
    }

    /// <inheritdoc />
    public Task<Result<RefreshedTokens, IDomainProblem>> RefreshAsync(
        string refreshToken,
        string resource,
        CancellationToken cancellationToken = default)
    {
        this.RefreshCount++;

        if (string.IsNullOrWhiteSpace(refreshToken))
        {
            return Task.FromResult(
                Result.Err<RefreshedTokens, IDomainProblem>(AuthProblems.MalformedToken()));
        }

        var next = this.Next(resource);
        if (next.IsFailure(out var failure))
        {
            return Task.FromResult(Result.Err<RefreshedTokens, IDomainProblem>(failure));
        }

        return Task.FromResult(
            Result.Ok<RefreshedTokens, IDomainProblem>(
                new RefreshedTokens(next.Get(), this.RotatedRefreshToken)));
    }

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> RevokeUserSessionsAsync(
        string userId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            return Task.FromResult(Result.Err<Unit, IDomainProblem>(AuthProblems.MalformedToken()));
        }

        if (this.RevokeOutcome.IsSuccess()) this._revoked.Add(userId);

        return Task.FromResult(this.RevokeOutcome);
    }

    private Result<TokenResponse, IDomainProblem> Next(string resource) =>
        this._scripted.TryGetValue(resource, out var queue) && queue.Count > 0
            ? queue.Dequeue()
            : this.Default;
}
