using System.Collections.Concurrent;
using AtomiCloud.Diene.AuthEngine.Onboarding;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// An in-memory onboarding backend for the demo, so OnboardSync composes without a database.
/// </summary>
/// <remarks>
/// This lives in <c>App</c> rather than being taken from a shipped TestHelper: the demo models a
/// real service, and a real service does not take a test dependency in production.
/// </remarks>
public sealed class DemoOnboardingBackend : IOnboardingBackend
{
    private readonly ConcurrentDictionary<string, string> _landscapes = new(StringComparer.Ordinal);

    /// <inheritdoc />
    public string BackendId => "demo-backend";

    /// <summary>Gets the home landscapes written so far.</summary>
    public IReadOnlyDictionary<string, string> Written => this._landscapes;

    /// <inheritdoc />
    public Task<Result<bool, IDomainProblem>> HasUserAsync(
        string subject,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(Result.Ok<bool, IDomainProblem>(this._landscapes.ContainsKey(subject)));
    }

    /// <inheritdoc />
    public Task<Result<Unit, IDomainProblem>> WriteHomeLandscapeAsync(
        string subject,
        string landscape,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        this._landscapes[subject] = landscape;
        return Task.FromResult(Result.Ok<Unit, IDomainProblem>(default));
    }
}
