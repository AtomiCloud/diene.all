using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems;

/// <summary>Describes a typed domain failure while keeping its metadata out of the payload.</summary>
public interface IDomainProblem
{
    /// <summary>Gets the stable snake_case wire identifier.</summary>
    [JsonIgnore]
    string Id { get; }

    /// <summary>Gets the human-readable problem title.</summary>
    [JsonIgnore]
    string Title { get; }

    /// <summary>Gets the instance-specific explanation.</summary>
    [JsonIgnore]
    string Detail { get; }

    /// <summary>Gets the versioned contract identity, such as <c>v1</c>.</summary>
    [JsonIgnore]
    string Version { get; }
}
