using AtomiCloud.Diene.Results;
using Microsoft.Extensions.Logging;

namespace AtomiCloud.Diene.Problems;

/// <summary>An immutable registry of versioned problem descriptors.</summary>
public sealed class ProblemCatalog : IProblemCatalog
{
    private readonly IReadOnlyDictionary<(string Version, string Id), ProblemDescriptor> _descriptors;
    private readonly ILogger<ProblemCatalog> _logger;

    internal ProblemCatalog(IReadOnlyList<ProblemDescriptor> descriptors, ILogger<ProblemCatalog> logger)
    {
        All = Array.AsReadOnly([.. descriptors]);
        _descriptors = descriptors.ToDictionary(descriptor => (descriptor.Version, descriptor.Id));
        _logger = logger;
    }

    /// <inheritdoc />
    public IReadOnlyList<ProblemDescriptor> All { get; }

    /// <inheritdoc />
    public Option<ProblemDescriptor> Find(string version, string id) =>
        _descriptors.TryGetValue((version, id), out var descriptor)
            ? Option.Some(descriptor)
            : Option.None<ProblemDescriptor>();

    /// <inheritdoc />
    public int StatusOf(IDomainProblem problem)
    {
        ArgumentNullException.ThrowIfNull(problem);
        var descriptor = Find(problem.Version, problem.Id);
        if (descriptor.IsSome() && descriptor.Get().Type == problem.GetType()) return descriptor.Get().Status;

        _logger.LogError(
            "Unregistered typed problem {ProblemType} ({ProblemVersion}/{ProblemId}) reached the HTTP boundary; returning 500",
            problem.GetType().FullName,
            problem.Version,
            problem.Id);
        return 500;
    }
}
