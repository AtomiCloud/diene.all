using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.Problems;

/// <summary>Provides immutable lookup and status policy for registered typed problems.</summary>
public interface IProblemCatalog
{
    /// <summary>Gets every registered descriptor.</summary>
    IReadOnlyList<ProblemDescriptor> All { get; }

    /// <summary>Finds a descriptor by version and wire identifier.</summary>
    Option<ProblemDescriptor> Find(string version, string id);

    /// <summary>Gets the registered HTTP status, returning 500 for an unknown typed problem.</summary>
    int StatusOf(IDomainProblem problem);
}
