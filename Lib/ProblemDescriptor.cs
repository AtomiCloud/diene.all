namespace AtomiCloud.Diene.Problems;

/// <summary>An HTTP endpoint associated with a problem catalog entry.</summary>
public sealed record ProblemEndpoint(string Method, string Path);

/// <summary>Registration metadata for one versioned typed problem.</summary>
public sealed record ProblemDescriptor(
    Type Type,
    string Id,
    string Title,
    string Version,
    int Status,
    bool Recoverable,
    IReadOnlyList<ProblemEndpoint> Endpoints);
