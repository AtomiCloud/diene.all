namespace AtomiCloud.Diene.Problems;

/// <summary>Carries a typed domain problem across a framework exception boundary.</summary>
public sealed class DomainProblemException(IDomainProblem problem) : Exception(problem?.Detail)
{
    /// <summary>Gets the typed problem carried by this exception.</summary>
    public IDomainProblem Problem { get; } = problem ?? throw new ArgumentNullException(nameof(problem));
}
