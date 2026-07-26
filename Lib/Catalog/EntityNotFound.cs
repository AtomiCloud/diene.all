using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems.Catalog;

/// <summary>A requested entity could not be found.</summary>
[Description("The requested entity could not be found by its identifier.")]
public sealed class EntityNotFound : IDomainProblem
{
    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public EntityNotFound()
    {
    }

    /// <summary>Creates a populated entity-not-found problem.</summary>
    public EntityNotFound(string detail, Type type, string requestIdentifier)
    {
        ArgumentNullException.ThrowIfNull(type);
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));
        RequestIdentifier = requestIdentifier ?? throw new ArgumentNullException(nameof(requestIdentifier));
        TypeName = type.FullName ?? "Unknown";
        AssemblyQualifiedName = type.AssemblyQualifiedName ?? "Unknown";
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "entity_not_found";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Entity Not Found";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets the identifier that was requested.</summary>
    [Description("The identifier of the requested entity.")]
    public string RequestIdentifier { get; } = string.Empty;

    /// <summary>Gets the full name of the requested entity type.</summary>
    [Description("The full name of the requested entity type.")]
    public string TypeName { get; } = string.Empty;

    /// <summary>Gets the assembly-qualified name of the requested entity type.</summary>
    [Description("The assembly-qualified name of the requested entity type.")]
    public string AssemblyQualifiedName { get; } = string.Empty;
}
