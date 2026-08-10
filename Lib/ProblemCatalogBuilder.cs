using System.Reflection;
using System.Text.RegularExpressions;
using AtomiCloud.Diene.Problems.Catalog;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace AtomiCloud.Diene.Problems;

/// <summary>Builds an immutable, consumer-registered problem catalog.</summary>
public sealed class ProblemCatalogBuilder
{
    private static readonly Regex MethodPattern = new("^[A-Z]+$", RegexOptions.CultureInvariant);
    private readonly Dictionary<(string Version, string Id), ProblemDescriptor> _descriptors = [];

    /// <summary>Registers one typed problem with its runtime and catalog metadata.</summary>
    public ProblemCatalogBuilder Add<T>(
        int status,
        bool recoverable,
        params ProblemEndpoint[] endpoints)
        where T : IDomainProblem, new()
    {
        ArgumentNullException.ThrowIfNull(endpoints);
        var problem = new T();
        return AddDescriptor(typeof(T), problem, status, recoverable, endpoints);
    }

    /// <summary>
    /// Registers parameterless problem types from an assembly after applying a caller-owned filter.
    /// </summary>
    public ProblemCatalogBuilder AddFromAssembly(
        Assembly assembly,
        Func<Type, bool> filter,
        Func<Type, int> statusOf,
        Func<Type, bool>? recoverableOf = null,
        Func<Type, IReadOnlyList<ProblemEndpoint>>? endpointsOf = null)
    {
        ArgumentNullException.ThrowIfNull(assembly);
        ArgumentNullException.ThrowIfNull(filter);
        ArgumentNullException.ThrowIfNull(statusOf);

        var types = assembly.DefinedTypes
            .Where(type => type is { IsAbstract: false, IsInterface: false } &&
                           typeof(IDomainProblem).IsAssignableFrom(type) &&
                           type.GetConstructor(Type.EmptyTypes) is not null)
            .Select(type => type.AsType())
            .Where(filter)
            .OrderBy(type => type.FullName, StringComparer.Ordinal);

        foreach (var type in types)
        {
            var problem = (IDomainProblem)Activator.CreateInstance(type)!;
            AddDescriptor(
                type,
                problem,
                statusOf(type),
                recoverableOf?.Invoke(type) ?? false,
                endpointsOf?.Invoke(type) ?? []);
        }

        return this;
    }

    /// <summary>Registers the seven portable baseline problems and their default policies.</summary>
    public ProblemCatalogBuilder AddBaseline() =>
        Add<EntityNotFound>(404, false)
            .Add<MultipleEntityNotFound>(404, false)
            .Add<EntityConflict>(409, true)
            .Add<ValidationError>(400, true)
            .Add<Unauthorized>(403, false)
            .Add<Unauthenticated>(401, true)
            .Add<InvalidJson>(400, true);

    /// <summary>Builds an immutable catalog, optionally using a consumer-provided logger.</summary>
    public ProblemCatalog Build(ILogger<ProblemCatalog>? logger = null) =>
        new([.. _descriptors.Values], logger ?? NullLogger<ProblemCatalog>.Instance);

    private ProblemCatalogBuilder AddDescriptor(
        Type type,
        IDomainProblem problem,
        int status,
        bool recoverable,
        IReadOnlyList<ProblemEndpoint> endpoints)
    {
        if (status is < 400 or > 599)
            throw new ArgumentOutOfRangeException(nameof(status), status, "Problem status must be between 400 and 599.");

        ProblemTypeUriBuilder.ValidateVersion(problem.Version);
        ProblemTypeUriBuilder.ValidateId(problem.Id);
        if (string.IsNullOrWhiteSpace(problem.Title))
            throw new ArgumentException("Problem title must not be blank.", nameof(problem));

        var validatedEndpoints = endpoints.Select(ValidateEndpoint).ToArray();
        var descriptor = new ProblemDescriptor(
            type,
            problem.Id,
            problem.Title,
            problem.Version,
            status,
            recoverable,
            Array.AsReadOnly(validatedEndpoints));

        if (!_descriptors.TryAdd((descriptor.Version, descriptor.Id), descriptor))
            throw new InvalidOperationException($"Problem {descriptor.Version}/{descriptor.Id} is already registered.");

        return this;
    }

    private static ProblemEndpoint ValidateEndpoint(ProblemEndpoint endpoint)
    {
        ArgumentNullException.ThrowIfNull(endpoint);
        if (endpoint.Method is null || !MethodPattern.IsMatch(endpoint.Method))
            throw new ArgumentException("Problem endpoint method must be uppercase.", nameof(endpoint));
        if (endpoint.Path is null || !endpoint.Path.StartsWith("/", StringComparison.Ordinal))
            throw new ArgumentException("Problem endpoint path must start with '/'.", nameof(endpoint));
        return new ProblemEndpoint(endpoint.Method, endpoint.Path);
    }
}
