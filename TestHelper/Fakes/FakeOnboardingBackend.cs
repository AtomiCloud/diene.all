using AtomiCloud.Diene.AuthEngine.Onboarding;
using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;

/// <summary>
/// An in-memory <see cref="IOnboardingBackend" />. The family table calls out per-backend
/// onboarding fakes as the reason this library ships a TestHelper at all: a consumer
/// cannot exercise the onboarding phase machine without standing in for its backend.
/// </summary>
public sealed class FakeOnboardingBackend : IOnboardingBackend
{
    private readonly HashSet<string> _known = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _landscapes = new(StringComparer.Ordinal);

    /// <summary>Creates a backend under a stable identifier.</summary>
    public FakeOnboardingBackend(string backendId = "fake-backend")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(backendId);
        this.BackendId = backendId;
    }

    /// <inheritdoc />
    public string BackendId { get; }

    /// <summary>Gets or sets a failure returned instead of answering the user probe.</summary>
    public IDomainProblem? ProbeFailure { get; set; }

    /// <summary>Gets or sets a failure returned instead of writing the claim.</summary>
    public IDomainProblem? WriteFailure { get; set; }

    /// <summary>Gets the home landscapes written so far, keyed by subject.</summary>
    public IReadOnlyDictionary<string, string> WrittenLandscapes => this._landscapes;

    /// <summary>Declares that the backend already has a record for the subject.</summary>
    public void WithKnownUser(string subject)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(subject);
        this._known.Add(subject);
    }

    /// <inheritdoc />
    public Task<Result<bool, IDomainProblem>> HasUserAsync(
        string subject,
        CancellationToken cancellationToken = default)
    {
        if (this.ProbeFailure is not null)
        {
            return Task.FromResult(Result.Err<bool, IDomainProblem>(this.ProbeFailure));
        }

        if (string.IsNullOrWhiteSpace(subject))
        {
            return Task.FromResult(Result.Err<bool, IDomainProblem>(AuthProblems.MalformedToken()));
        }

        return Task.FromResult(Result.Ok<bool, IDomainProblem>(this._known.Contains(subject)));
    }

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> WriteHomeLandscapeAsync(
        string subject,
        string landscape,
        CancellationToken cancellationToken = default)
    {
        if (this.WriteFailure is not null)
        {
            return Task.FromResult(Result.Err<Unit, IDomainProblem>(this.WriteFailure));
        }

        if (string.IsNullOrWhiteSpace(subject) || string.IsNullOrWhiteSpace(landscape))
        {
            return Task.FromResult(Result.Err<Unit, IDomainProblem>(AuthProblems.MalformedToken()));
        }

        // Writing the claim also makes the subject known, mirroring the real backend:
        // after OnboardSync there is a user record. A fake that recorded the landscape
        // without the record would let a test pass against a state the real system
        // cannot be in.
        this._landscapes[subject] = landscape;
        this._known.Add(subject);
        return Task.FromResult(Result.Ok<Unit, IDomainProblem>(new Unit()));
    }
}
