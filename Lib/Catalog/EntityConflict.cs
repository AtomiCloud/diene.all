using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems.Catalog;

/// <summary>An entity conflicts with an existing unique value or state.</summary>
[Description("An entity conflicts with an existing unique value or state.")]
public sealed class EntityConflict : IDomainProblem
{
    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public EntityConflict()
    {
    }

    /// <summary>Creates a populated entity-conflict problem.</summary>
    public EntityConflict(string detail, Type type)
    {
        ArgumentNullException.ThrowIfNull(type);
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));
        TypeName = type.FullName ?? "Unknown";
        AssemblyQualifiedName = type.AssemblyQualifiedName ?? "Unknown";
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "entity_conflict";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Entity Conflict";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets the full name of the conflicting entity type.</summary>
    [Description("The full name of the conflicting entity type.")]
    public string TypeName { get; } = string.Empty;

    /// <summary>Gets the assembly-qualified name of the conflicting entity type.</summary>
    [Description("The assembly-qualified name of the conflicting entity type.")]
    public string AssemblyQualifiedName { get; } = string.Empty;
}
