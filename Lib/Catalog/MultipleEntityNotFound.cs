using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems.Catalog;

/// <summary>Some entities in a batch request could not be found.</summary>
[Description("Some requested entities could not be found during a batch request.")]
public sealed class MultipleEntityNotFound : IDomainProblem
{
    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public MultipleEntityNotFound()
    {
    }

    /// <summary>Creates a populated batch-not-found problem.</summary>
    public MultipleEntityNotFound(
        string detail,
        Type type,
        IEnumerable<string> requestIdentifiers,
        IEnumerable<string> foundRequestIdentifiers)
    {
        ArgumentNullException.ThrowIfNull(type);
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));
        RequestIdentifiers = [.. requestIdentifiers ?? throw new ArgumentNullException(nameof(requestIdentifiers))];
        FoundRequestIdentifiers = [.. foundRequestIdentifiers ?? throw new ArgumentNullException(nameof(foundRequestIdentifiers))];
        TypeName = type.FullName ?? "Unknown";
        AssemblyQualifiedName = type.AssemblyQualifiedName ?? "Unknown";
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "multiple_entity_not_found";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Multiple Entity Not Found";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets identifiers that were not found.</summary>
    [Description("Identifiers of requested entities that were not found.")]
    public IReadOnlyList<string> RequestIdentifiers { get; } = [];

    /// <summary>Gets identifiers that were found.</summary>
    [Description("Identifiers of requested entities that were found.")]
    public IReadOnlyList<string> FoundRequestIdentifiers { get; } = [];

    /// <summary>Gets the full name of the requested entity type.</summary>
    [Description("The full name of the requested entity type.")]
    public string TypeName { get; } = string.Empty;

    /// <summary>Gets the assembly-qualified name of the requested entity type.</summary>
    [Description("The assembly-qualified name of the requested entity type.")]
    public string AssemblyQualifiedName { get; } = string.Empty;
}
