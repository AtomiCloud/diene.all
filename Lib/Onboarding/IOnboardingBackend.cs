using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Onboarding;

/// <summary>
/// The per-backend onboarding boundary. Each backend answers whether it knows the user
/// and writes the home-landscape claim when a landscape is picked. This is the seam the
/// family table calls out as needing per-backend fakes, and the shipped TestHelper
/// provides one.
/// </summary>
public interface IOnboardingBackend
{
    /// <summary>Gets the backend's stable identifier, used to key registrations.</summary>
    string BackendId { get; }

    /// <summary>
    /// Whether this backend has a user record for the subject. Corresponds to the
    /// <c>GET /User/Me</c> probe: absent is a normal answer, not a failure.
    /// </summary>
    Task<Result<bool, IDomainProblem>> HasUserAsync(
        string subject,
        CancellationToken cancellationToken = default);

    /// <summary>Writes the user's home-landscape claim, completing onboarding.</summary>
    Task<Result<Unit, IDomainProblem>> WriteHomeLandscapeAsync(
        string subject,
        string landscape,
        CancellationToken cancellationToken = default);
}
